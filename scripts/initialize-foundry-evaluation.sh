#!/usr/bin/env bash
# Follows .github/instructions/wow-follow-up-question.instructions.md.
set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
environment="${AZURE_ENV_NAME:-}"
configuration_directory="$repository_root/infra/foundry"
validate_only=false

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --environment|--configuration-directory)
            [[ $# -ge 2 && -n "${2:-}" ]] || fail "Missing value for $1."
            if [[ "$1" == --environment ]]; then environment="$2"; else configuration_directory="$2"; fi
            shift 2
            ;;
        --validate-only) validate_only=true; shift ;;
        --help)
            printf '%s\n' 'Usage: bash scripts/initialize-foundry-evaluation.sh [--environment NAME] [--configuration-directory PATH] [--validate-only]'
            exit 0
            ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

command -v jq >/dev/null || fail 'jq is required to provision Foundry evaluations.'
if command -v sha256sum >/dev/null; then
    hash_command=(sha256sum)
elif command -v shasum >/dev/null; then
    hash_command=(shasum -a 256)
else
    fail 'sha256sum or shasum is required to hash evaluator definitions.'
fi

json() {
    jq "$@" | tr -d '\r'
}

content_hash() {
    local canonical
    canonical="$(printf '%s' "$1" | json -cS .)"
    printf '%s' "$canonical" | "${hash_command[@]}" | cut -d ' ' -f 1
}

configuration="$(json -c . "$configuration_directory/evaluation.json")"
definitions="$(json -c . "$configuration_directory/evaluators.json")"
if ! printf '%s' "$configuration" | json -e '
    . as $configuration |
    (.EvaluationName | type == "string" and test("\\S")) and
    (.ModelDeploymentName | type == "string" and test("\\S")) and
    all(["QualityPassThreshold", "CommunicationPassThreshold", "SafetySeverityThreshold"][];
        . as $setting | $configuration[$setting] as $value |
        ($value | type) == "number" and $value == ($value | floor) and
        $value >= (if $setting == "SafetySeverityThreshold" then 0 else 1 end) and
        $value <= (if $setting == "SafetySeverityThreshold" then 7 else 5 end)) and
    (.Evaluators | type == "array" and length > 0 and length == (unique | length) and all(.[]; type == "string"))
' >/dev/null; then
    fail 'Invalid evaluation configuration: names, integer thresholds and a nonempty array of unique evaluator names are required.'
fi

custom_evaluators='[]'
criteria='[]'
while IFS= read -r name; do
    catalog_name="$name"
    if printf '%s' "$definitions" | json -e --arg name "$name" 'has($name)' >/dev/null; then
        entry="$(printf '%s' "$definitions" | json -c --arg name "$name" '.[$name]')"
        source_file="$(printf '%s' "$entry" | json -er '.source_file | select(type == "string")')"
        [[ "$source_file" =~ ^[a-z0-9_]+\.(py|txt)$ ]] || fail "Invalid source file for evaluator '$name'."
        definition_type="$(printf '%s' "$entry" | json -r '.evaluator.definition.type')"
        case "$definition_type" in
            code) source_property=code_text ;;
            prompt) source_property=prompt_text ;;
            *) fail "Unsupported evaluator definition type for '$name'." ;;
        esac
        custom="$(printf '%s' "$entry" | json -c --rawfile source "$configuration_directory/$source_file" --arg property "$source_property" '
            if ($source | test("\\S")) then
                .evaluator.definition[$property] = ($source | gsub("\r\n"; "\n")) | {evaluator: .evaluator}
            else error("Evaluator source must not be empty.") end')"
        definition="$(printf '%s' "$custom" | json -c '.evaluator.definition')"
        definition_hash="$(content_hash "$definition")"
        catalog_name="${name}_${definition_hash:0:12}"
        custom="$(printf '%s' "$custom" | json -c --arg name "$catalog_name" '. + {name: $name}')"
        custom_evaluators="$(printf '%s' "$custom_evaluators" | json -c --argjson custom "$custom" '. + [$custom]')"
    else
        case "$name" in
            builtin.relevance|builtin.coherence|builtin.fluency|builtin.violence) ;;
            *) fail "Unsupported evaluator '$name'." ;;
        esac
    fi
    criterion="$(json -cn --arg name "$name" --arg catalog "$catalog_name" --argjson configuration "$configuration" '{
        type: "azure_ai_evaluator",
        name: ($name | sub("^builtin\\."; "")),
        evaluator_name: $catalog,
        data_mapping: ({response: "{{item.response}}"} +
            if $name == "builtin.fluency" or $name == "official_microsoft_links" then {} else {query: "{{item.query}}"} end),
        initialization_parameters: (
            if $name == "builtin.violence" then {threshold: $configuration.SafetySeverityThreshold}
            else {deployment_name: $configuration.ModelDeploymentName} +
                if $name == "official_microsoft_links" then {pass_threshold: 1}
                elif $name == "corporate_communication" then {threshold: $configuration.CommunicationPassThreshold}
                else {threshold: $configuration.QualityPassThreshold} end
            end)
    }')"
    criteria="$(printf '%s' "$criteria" | json -c --argjson criterion "$criterion" '. + [$criterion]')"
done < <(printf '%s' "$configuration" | json -r '.Evaluators[]')

fingerprint_input="$(json -cn --argjson criteria "$criteria" '{scenario: "traces", testing_criteria: $criteria}')"
fingerprint="$(content_hash "$fingerprint_input")"
request="$(json -cn --argjson configuration "$configuration" --argjson criteria "$criteria" --arg fingerprint "$fingerprint" '{
    name: $configuration.EvaluationName,
    data_source_config: {type: "azure_ai_source", scenario: "traces"},
    testing_criteria: $criteria,
    metadata: {configuration_hash: $fingerprint}
}')"
if [[ "$validate_only" == true ]]; then
    json -n --argjson custom "$custom_evaluators" --argjson evaluation "$request" '{CustomEvaluators: $custom, Evaluation: $evaluation}'
    exit 0
fi

[[ -n "$environment" ]] || fail 'AZURE_ENV_NAME must be set, or pass --environment. Run this script through azd postprovision.'
command -v az >/dev/null || fail 'Azure CLI is required to provision Foundry evaluations.'
command -v azd >/dev/null || fail 'Azure Developer CLI is required to read the selected environment.'
project_endpoint="$(azd env get-value FOUNDRY_PROJECT_ENDPOINT --environment "$environment" --cwd "$repository_root")" ||
    fail 'Cannot read FOUNDRY_PROJECT_ENDPOINT from the azd environment.'
project_endpoint="$(printf '%s' "$project_endpoint" | json -Rr 'gsub("^\\s+|\\s+$"; "")')"
project_endpoint="${project_endpoint%/}"
[[ "$project_endpoint" =~ ^https://[a-zA-Z0-9.-]+\.services\.ai\.azure\.com(:443)?/api/projects/[a-zA-Z0-9_-]+$ ]] ||
    fail 'FOUNDRY_PROJECT_ENDPOINT must be an HTTPS Microsoft Foundry project endpoint.'

umask 077
temporary_directory="$(mktemp -d)"
trap 'rm -rf -- "$temporary_directory"' EXIT

invoke_foundry_request() {
    local method="$1" url="$2" body="${3:-}" path output
    [[ "$url" == "$project_endpoint/"* ]] || fail 'Foundry returned a continuation URL outside the selected project.'
    path="${url#"$project_endpoint"}"
    [[ "$path" =~ ^/(evaluators(/[a-zA-Z0-9_-]+/versions)?|openai/v1/evals)(\?[^#]*)?$ ]] ||
        fail 'Foundry returned a continuation URL outside the selected project evaluation APIs.'
    local arguments=(rest --method "$method" --url "$url" --resource https://ai.azure.com --output json --only-show-errors
        --headers Foundry-Features=Evaluations=V1Preview Content-Type=application/json)
    if [[ -n "$body" ]]; then
        printf '%s' "$body" > "$temporary_directory/request.json"
        arguments+=(--body "@$temporary_directory/request.json")
    fi
    if ! output="$(az "${arguments[@]}")"; then
        fail "Foundry $method failed. Check Azure CLI authentication, project readiness and deployment identity permissions."
    fi
    printf '%s' "$output" | json -c .
}

resolve_next_page() {
    local current="$1" link="$2" base
    case "$link" in
        https://*) printf '%s' "$link" ;;
        //*) printf 'https:%s' "$link" ;;
        /*) printf '%s%s' "${project_endpoint%%/api/projects/*}" "$link" ;;
        \?*) printf '%s%s' "${current%%\?*}" "$link" ;;
        *)
            base="${current%%\?*}"
            base="${base%/*}"
            while [[ "$link" == ../* ]]; do base="${base%/*}"; link="${link#../}"; done
            while [[ "$link" == ./* ]]; do link="${link#./}"; done
            printf '%s/%s' "$base" "$link"
            ;;
    esac
}

visited_pages='[]'
check_pagination() {
    printf '%s' "$visited_pages" | json -e --arg url "$1" 'index($url) == null' >/dev/null ||
        fail 'Foundry pagination did not advance.'
    visited_pages="$(printf '%s' "$visited_pages" | json -c --arg url "$1" '. + [$url]')"
}

existing_evaluators='[]'
next_page="$project_endpoint/evaluators?api-version=v1&type=custom&limit=100"
while [[ -n "$next_page" ]]; do
    check_pagination "$next_page"
    page="$(invoke_foundry_request get "$next_page")"
    printf '%s' "$page" | json -e '.value | type == "array"' >/dev/null || fail 'Invalid evaluator catalog response.'
    existing_evaluators="$(printf '%s' "$existing_evaluators" | json -c --argjson page "$page" '. + $page.value')"
    continuation="$(printf '%s' "$page" | json -r '.nextLink // empty')"
    if [[ -n "$continuation" ]]; then next_page="$(resolve_next_page "$next_page" "$continuation")"; else next_page=''; fi
done
while IFS= read -r custom; do
    name="$(printf '%s' "$custom" | json -r '.name')"
    existing="$(printf '%s' "$existing_evaluators" | json -c --arg name "$name" '[.[] | select(.name == $name)] | last // null')"
    if [[ "$existing" != null ]]; then
        if ! printf '%s' "$existing" | json -e --argjson custom "$custom" '
            .definition | (if $custom.evaluator.definition.type == "code" then "prompt_text" else "code_text" end) as $inactive |
            (if .[$inactive] == "" then del(.[$inactive]) else . end) == $custom.evaluator.definition' >/dev/null; then
            fail "Custom evaluator '$name' exists with a different definition."
        fi
        printf "Reusing Foundry custom evaluator '%s'.\n" "$name"
    else
        body="$(printf '%s' "$custom" | json -c '.evaluator')"
        encoded_name="$(json -nr --arg name "$name" '$name | @uri')"
        registered="$(invoke_foundry_request post "$project_endpoint/evaluators/$encoded_name/versions?api-version=v1" "$body")"
        printf '%s' "$registered" | json -e --arg name "$name" '.name == $name and (.version | type == "string" and test("\\S"))' >/dev/null ||
            fail 'Foundry did not return the published evaluator name and version.'
        printf "Published Foundry custom evaluator '%s', version '%s'.\n" "$name" "$(printf '%s' "$registered" | json -r '.version')"
    fi
done < <(printf '%s' "$custom_evaluators" | json -c '.[]')

evaluation_id=''
after=''
while :; do
    url="$project_endpoint/openai/v1/evals?limit=100&order=asc&order_by=created_at"
    if [[ -n "$after" ]]; then url+="&after=$(json -nr --arg after "$after" '$after | @uri')"; fi
    check_pagination "$url"
    page="$(invoke_foundry_request get "$url")"
    printf '%s' "$page" | json -e '.data | type == "array"' >/dev/null || fail 'Invalid evaluation group response.'
    existing="$(printf '%s' "$page" | json -c --argjson request "$request" '
        [.data[] | select(.name == $request.name and .metadata.configuration_hash? == $request.metadata.configuration_hash)] | first // null')"
    if [[ "$existing" != null ]]; then
        if ! printf '%s' "$existing" | json -e --argjson criteria "$criteria" '
            [.testing_criteria[] | del(.id) | if .evaluator_version == "" then del(.evaluator_version) else . end] == $criteria' >/dev/null; then
            fail 'The matching Foundry evaluation group has different testing criteria.'
        fi
        evaluation_id="$(printf '%s' "$existing" | json -r '.id')"
        printf "Reusing Foundry evaluation group '%s' (%s).\n" "$(printf '%s' "$request" | json -r '.name')" "$evaluation_id"
        break
    fi
    [[ "$(printf '%s' "$page" | json -r '.has_more // false')" == true ]] || break
    after="$(printf '%s' "$page" | json -er '.last_id | select(type == "string" and length > 0)')" || fail 'Foundry evaluation pagination did not advance.'
done
if [[ -z "$evaluation_id" ]]; then
    created="$(invoke_foundry_request post "$project_endpoint/openai/v1/evals" "$request")"
    evaluation_id="$(printf '%s' "$created" | json -r '.id')"
    printf "Created Foundry evaluation group '%s' (%s).\n" "$(printf '%s' "$request" | json -r '.name')" "$evaluation_id"
fi
[[ "$evaluation_id" =~ ^eval_[a-zA-Z0-9_-]+$ ]] || fail 'Foundry did not return a valid evaluation group ID.'
azd env set FOUNDRY_EVALUATION_ID "$evaluation_id" --environment "$environment" --cwd "$repository_root" ||
    fail 'Cannot save FOUNDRY_EVALUATION_ID to the azd environment.'
printf '%s\n' 'Foundry evaluation provisioning completed. No agent requests or evaluation runs were submitted.'
