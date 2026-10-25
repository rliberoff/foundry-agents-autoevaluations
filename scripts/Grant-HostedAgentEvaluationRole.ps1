#Requires -Version 7.0
# Follows .github/instructions/wow-follow-up-question.instructions.md.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$environment = $env:AZURE_ENV_NAME
if ([string]::IsNullOrWhiteSpace($environment)) {
    throw 'AZURE_ENV_NAME must be set. Run this script through the azd postdeploy hook.'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$roleId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

function Get-AzdValue([string] $Name) {
    $value = azd env get-value $Name --environment $environment --cwd $repositoryRoot
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($value)) {
        throw "Cannot read '$Name' from azd environment '$environment'."
    }
    return $value.Trim()
}

$subscriptionId = Get-AzdValue 'AZURE_SUBSCRIPTION_ID'
$resourceGroup = Get-AzdValue 'AZURE_RESOURCE_GROUP'
$accountName = Get-AzdValue 'AZURE_AI_ACCOUNT_NAME'
$scope = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$accountName"

$agentJson = azd ai agent show agent-autoevaluations --environment $environment --cwd $repositoryRoot --output json --no-prompt
if ($LASTEXITCODE -ne 0) {
    throw 'Cannot read the deployed hosted agent identity.'
}
$principalId = ($agentJson | ConvertFrom-Json).instance_identity.principal_id
if ($principalId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
    throw 'The deployed hosted agent did not return a valid principal ID.'
}

$existingAssignment = az role assignment list --subscription $subscriptionId --scope $scope `
    --assignee-object-id $principalId --role $roleId --fill-principal-name false `
    --fill-role-definition-name false --query '[?condition==null].id' --output tsv --only-show-errors
if ($LASTEXITCODE -ne 0) {
    throw 'Cannot check the hosted agent role assignment. Authenticate Azure CLI and verify RBAC read permissions.'
}

if ([string]::IsNullOrWhiteSpace($existingAssignment)) {
    az role assignment create --subscription $subscriptionId --scope $scope `
        --assignee-object-id $principalId --assignee-principal-type ServicePrincipal `
        --role $roleId --output none --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot grant Foundry User to the hosted agent. The deployment identity needs Microsoft.Authorization/roleAssignments/write on the Foundry account.'
    }
    Write-Host 'Granted Foundry User to the hosted agent on its Foundry account.'
}
else {
    Write-Host 'The hosted agent already has Foundry User on its Foundry account.'
}

Write-Host 'RBAC propagation may take time. An initial evaluation permission failure is retried at the configured polling interval.'
