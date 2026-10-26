#!/usr/bin/env bash
# Follows .github/instructions/wow-follow-up-question.instructions.md.
set -euo pipefail

environment="${AZURE_ENV_NAME:?AZURE_ENV_NAME is required.}"
if [[ ! "$environment" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
    printf '%s\n' 'Invalid AZURE_ENV_NAME.' >&2
    exit 1
fi

project_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for relative_path in \
    '.azure' \
    ".azure/$environment" \
    ".azure/$environment/infra" \
    ".azure/$environment/infra/backend" \
    ".azure/$environment/infra/backend/terraform.tfstate" \
    ".azure/$environment/infra/resources" \
    ".azure/$environment/infra/resources/.terraform"; do
    if [[ -L "$project_directory/$relative_path" ]]; then
        printf 'Refusing to reset Terraform cache through a linked path: %s\n' "$relative_path" >&2
        exit 1
    fi
done

state_path="$project_directory/.azure/$environment/infra/backend/terraform.tfstate"
cache_path="$project_directory/.azure/$environment/infra/resources/.terraform"
if [[ ! -e "$cache_path" ]]; then
    printf '%s\n' 'Terraform backend cache is already absent.'
    exit 0
fi
if [[ ! -f "$state_path" ]]; then
    printf '%s\n' 'Keeping Terraform backend cache: no local backend state proves teardown completed.'
    exit 0
fi

jq -e 'type == "object" and .version == 4 and (.resources | type == "array") and (.outputs | type == "object") and all(.resources[]; type == "object" and (.mode == "managed" or .mode == "data"))' \
    "$state_path" >/dev/null
if ! jq -e '([.resources[] | select(.mode == "managed")] | length) == 0 and (.outputs | length) == 0' \
    "$state_path" >/dev/null; then
    printf '%s\n' 'Keeping Terraform backend cache: backend resources or outputs remain.'
    exit 0
fi

rm -rf -- "$cache_path"
printf "Reset Terraform backend initialization cache for environment '%s'.\n" "$environment"
