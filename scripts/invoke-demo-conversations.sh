#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf '%s\n' \
        'Usage: bash scripts/invoke-demo-conversations.sh --environment NAME [options]' \
        '  --conversation-count NUMBER  Conversations to send, 1-1000 (default: 6)' \
        '  --conversation-type microsoft|generic  Scenario topic (default: microsoft)' \
        '  --language en|es|mixed        Scenario language (default: en)' \
        '  --timeout-seconds NUMBER     Timeout per request, 1-3600 (default: 300)' \
        '  --delay-seconds NUMBER       Delay between requests, 0-3600 (default: 10)' \
        '  --dry-run                    Print prompts without calling azd or Azure' \
        '  --help                       Show this help' \
        'Live execution incurs charges and updates the saved azd conversation.' \
        'Follow-up and confidence rule: .github/instructions/wow-follow-up-question.instructions.md.'
}

fail() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

environment=''
conversation_count=6
conversation_type=microsoft
language=en
timeout_seconds=300
delay_seconds=10
dry_run=false

while (($# > 0)); do
    case "$1" in
        --environment|--conversation-count|--conversation-type|--language|--timeout-seconds|--delay-seconds)
            (($# >= 2)) || fail "Missing value for $1."
            case "$1" in
                --environment) environment=$2 ;;
                --conversation-count) conversation_count=$2 ;;
                --conversation-type) conversation_type=$2 ;;
                --language) language=$2 ;;
                --timeout-seconds) timeout_seconds=$2 ;;
                --delay-seconds) delay_seconds=$2 ;;
            esac
            shift 2
            ;;
        --dry-run) dry_run=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) fail "Unknown option: $1. Use --help." ;;
    esac
done

[[ -n ${environment//[[:space:]]/} ]] || fail '--environment is required.'
[[ $conversation_count =~ ^[1-9][0-9]{0,3}$ ]] || fail '--conversation-count must be an integer from 1 to 1000.'
((conversation_count <= 1000)) || fail '--conversation-count must be an integer from 1 to 1000.'
[[ $timeout_seconds =~ ^[1-9][0-9]{0,3}$ ]] || fail '--timeout-seconds must be an integer from 1 to 3600.'
((timeout_seconds <= 3600)) || fail '--timeout-seconds must be an integer from 1 to 3600.'
[[ $delay_seconds =~ ^(0|[1-9][0-9]{0,3})$ ]] || fail '--delay-seconds must be an integer from 0 to 3600.'
((delay_seconds <= 3600)) || fail '--delay-seconds must be an integer from 0 to 3600.'
[[ $language == en || $language == es || $language == mixed ]] || fail '--language must be en, es or mixed.'
[[ $conversation_type == microsoft || $conversation_type == generic ]] || fail '--conversation-type must be microsoft or generic.'
command -v jq >/dev/null 2>&1 || fail 'jq is required, including for --dry-run. See demo.es.md for setup.'

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(cd -- "$script_directory/.." && pwd)
catalog_file=demo-conversations.json
if [[ $conversation_type == generic ]]; then
    catalog_file=demo-conversations-generic.json
fi
scenarios=$(jq -ce --arg language "$language" '
    map(select($language == "mixed" or .language == $language))
    | if length > 0 and all(.[];
        (.name | type == "string" and test("\\S")) and
        (.turns | type == "array" and length > 0 and all(.[]; type == "string" and test("\\S"))))
      then . else error("Each selected scenario needs a name and nonempty string turns.") end
' "$script_directory/$catalog_file")
scenario_count=$(jq 'length' <<< "$scenarios")

if [[ $dry_run == false ]]; then
    command -v azd >/dev/null 2>&1 || fail 'Azure Developer CLI (azd) is required. See demo.es.md for setup.'
    if ! invoke_help=$(azd ai agent invoke --help 2>&1); then
        fail 'Unable to read azd agent invoke help. See demo.es.md for extension setup.'
    fi
    [[ $invoke_help == *--new-conversation* ]] || fail 'The installed azd agent extension must support --new-conversation.'
    printf '%s\n' \
        'LIVE RUN: model calls and automatic evaluations can incur charges. Press Ctrl+C to stop.' \
        'Do not invoke this agent from another CLI process while this script runs.'
fi

sent_turns=0
printf 'Start UTC: %s | Environment: %s | Conversations: %s | Type: %s | Language: %s | Delay seconds: %s | Dry run: %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$environment" "$conversation_count" "$conversation_type" "$language" "$delay_seconds" "$dry_run"

for ((conversation_index = 0; conversation_index < conversation_count; conversation_index++)); do
    scenario=$(jq -c --argjson index "$((conversation_index % scenario_count))" '.[$index]' <<< "$scenarios")
    scenario_name=$(jq -r '.name' <<< "$scenario")
    turn_count=$(jq '.turns | length' <<< "$scenario")
    printf 'Conversation %s/%s: %s\n' "$((conversation_index + 1))" "$conversation_count" "$scenario_name"

    for ((turn_index = 0; turn_index < turn_count; turn_index++)); do
        prompt=$(jq -r --argjson index "$turn_index" '.turns[$index]' <<< "$scenario")
        invoke_arguments=(
            ai agent invoke agent-autoevaluations "$prompt"
            --cwd "$repository_root"
            --environment "$environment"
            --protocol responses
            --timeout "$timeout_seconds"
            --output raw
            --no-prompt
        )
        if ((turn_index == 0)); then
            invoke_arguments+=(--new-conversation)
        fi

        printf '  Turn %s/%s: %s\n' "$((turn_index + 1))" "$turn_count" "$prompt"
        if [[ $dry_run == false ]]; then
            if ((sent_turns > 0 && delay_seconds > 0)); then
                printf 'Waiting %s seconds before the next request.\n' "$delay_seconds"
                sleep "$delay_seconds"
            fi
            if ! raw_response=$(azd "${invoke_arguments[@]}"); then
                printf 'Invocation failed at conversation %s, turn %s. Stopped without retry; %s previous turns succeeded. Check azd authentication, agent status, permissions and quota.\n' \
                    "$((conversation_index + 1))" "$((turn_index + 1))" "$sent_turns" >&2
                exit 1
            fi
            if ! response_text=$(jq --raw-input --slurp --exit-status --raw-output '
                [split("\n")[] | rtrimstr("\r")
                    | select(startswith("data: ")) | ltrimstr("data: ")
                    | select(. != "[DONE]") | fromjson
                    | select(.type == "response.completed") | .response]
                | last | select(.status == "completed")
                | [.output[]? | select(.type == "message" and .role == "assistant")
                    | .content[]? | select(.type == "output_text") | .text]
                | join("\n") | select(test("\\S"))
            ' <<< "$raw_response"); then
                printf 'No completed text response at conversation %s, turn %s. Stopped without retry; %s previous turns succeeded. Inspect the agent and its Responses stream.\n' \
                    "$((conversation_index + 1))" "$((turn_index + 1))" "$sent_turns" >&2
                exit 1
            fi
            printf '%s\n' "$response_text"
        fi
        sent_turns=$((sent_turns + 1))
    done
done

printf 'End UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ $dry_run == true ]]; then
    printf 'Dry run complete: %s conversations, %s planned requests. No Azure calls were made.\n' "$conversation_count" "$sent_turns"
else
    printf 'Completed: %s conversations, %s successful CLI requests. Verify trace ingestion and evaluation results separately.\n' "$conversation_count" "$sent_turns"
fi
