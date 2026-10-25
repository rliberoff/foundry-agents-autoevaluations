#!/usr/bin/env bash
# Follows .github/instructions/wow-follow-up-question.instructions.md.
set -euo pipefail

environment="${AZURE_ENV_NAME:?AZURE_ENV_NAME must be set by the azd postdeploy hook.}"
repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
role_id='53ca6127-db72-4b80-b1b0-d745d6d5456d'

command -v jq >/dev/null || { printf '%s\n' 'jq is required to read the hosted agent identity.' >&2; exit 1; }

get_azd_value() {
    local value
    if ! value="$(azd env get-value "$1" --environment "$environment" --cwd "$repository_root")" || [[ -z "$value" ]]; then
        printf "Cannot read '%s' from azd environment '%s'.\n" "$1" "$environment" >&2
        return 1
    fi
    printf '%s' "$value"
}

subscription_id="$(get_azd_value AZURE_SUBSCRIPTION_ID)"
resource_group="$(get_azd_value AZURE_RESOURCE_GROUP)"
account_name="$(get_azd_value AZURE_AI_ACCOUNT_NAME)"
scope="/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.CognitiveServices/accounts/$account_name"

principal_id="$(azd ai agent show agent-autoevaluations --environment "$environment" --cwd "$repository_root" --output json --no-prompt |
    jq -er '.instance_identity.principal_id | select(type == "string")')"
if [[ ! "$principal_id" =~ ^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$ ]]; then
    printf '%s\n' 'The deployed hosted agent did not return a valid principal ID.' >&2
    exit 1
fi

if ! existing_assignment="$(az role assignment list --subscription "$subscription_id" --scope "$scope" \
    --assignee-object-id "$principal_id" --role "$role_id" --fill-principal-name false \
    --fill-role-definition-name false --query '[?condition==null].id' --output tsv --only-show-errors)"; then
    printf '%s\n' 'Cannot check the hosted agent role assignment. Authenticate Azure CLI and verify RBAC read permissions.' >&2
    exit 1
fi

if [[ -z "$existing_assignment" ]]; then
    if ! az role assignment create --subscription "$subscription_id" --scope "$scope" \
        --assignee-object-id "$principal_id" --assignee-principal-type ServicePrincipal \
        --role "$role_id" --output none --only-show-errors; then
        printf '%s\n' 'Cannot grant Foundry User to the hosted agent. The deployment identity needs Microsoft.Authorization/roleAssignments/write on the Foundry account.' >&2
        exit 1
    fi
    printf '%s\n' 'Granted Foundry User to the hosted agent on its Foundry account.'
else
    printf '%s\n' 'The hosted agent already has Foundry User on its Foundry account.'
fi

printf '%s\n' 'RBAC propagation may take time. An initial evaluation permission failure is retried at the configured polling interval.'
