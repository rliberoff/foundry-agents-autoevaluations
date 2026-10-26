#Requires -Version 7.4
# Follows .github/instructions/wow-follow-up-question.instructions.md.

[CmdletBinding()]
param(
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9_-]*$')]
    [Parameter(Mandatory = $false)]
    [string] $Environment = $env:AZURE_ENV_NAME
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($Environment)) {
    throw 'AZURE_ENV_NAME is required.'
}
if ($Environment -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*$') {
    throw 'Invalid AZURE_ENV_NAME.'
}

$projectDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$relativePaths = @(
    '.azure',
    ".azure/$Environment",
    ".azure/$Environment/infra",
    ".azure/$Environment/infra/backend",
    ".azure/$Environment/infra/backend/terraform.tfstate",
    ".azure/$Environment/infra/resources",
    ".azure/$Environment/infra/resources/.terraform"
)
foreach ($relativePath in $relativePaths) {
    $path = Join-Path $projectDirectory $relativePath
    if ((Test-Path -LiteralPath $path) -and
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing to reset Terraform cache through a linked path: $relativePath"
    }
}

$statePath = Join-Path $projectDirectory ".azure/$Environment/infra/backend/terraform.tfstate"
$cachePath = Join-Path $projectDirectory ".azure/$Environment/infra/resources/.terraform"
if (-not (Test-Path -LiteralPath $cachePath)) {
    Write-Host 'Terraform backend cache is already absent.'
    return
}
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    Write-Host 'Keeping Terraform backend cache: no local backend state proves teardown completed.'
    return
}

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
if ($state.version -ne 4 -or $state.resources -isnot [array] -or
    $state.outputs -isnot [System.Collections.IDictionary]) {
    throw 'Unsupported or incomplete local backend state; Terraform cache was not reset.'
}
foreach ($resource in $state.resources) {
    if ($resource -isnot [System.Collections.IDictionary] -or
        $resource.mode -notin @('managed', 'data')) {
        throw 'Invalid resource in local backend state; Terraform cache was not reset.'
    }
}
if (@($state.resources | Where-Object { $_.mode -eq 'managed' }).Count -gt 0 -or
    $state.outputs.Count -gt 0) {
    Write-Host 'Keeping Terraform backend cache: backend resources or outputs remain.'
    return
}

Remove-Item -LiteralPath $cachePath -Recurse -Force
Write-Host "Reset Terraform backend initialization cache for environment '$Environment'."
