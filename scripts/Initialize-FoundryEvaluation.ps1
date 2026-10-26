#Requires -Version 7.4
# Follows .github/instructions/wow-follow-up-question.instructions.md.

[CmdletBinding()]
param(
    [string] $Environment = $env:AZURE_ENV_NAME,
    [string] $ConfigurationDirectory = (Join-Path $PSScriptRoot '../infra/foundry'),
    [switch] $ValidateOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function ConvertTo-CanonicalValue($Value) {
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        $keys = [string[]] @($Value.Keys)
        [Array]::Sort($keys, [StringComparer]::Ordinal)
        foreach ($key in $keys) {
            $result[$key] = ConvertTo-CanonicalValue $Value[$key]
        }
        return $result
    }
    if ($Value -is [array]) {
        return ,@($Value | ForEach-Object { ConvertTo-CanonicalValue $_ })
    }
    return $Value
}

function Get-CanonicalJson($Value) {
    return ConvertTo-Json -InputObject (ConvertTo-CanonicalValue $Value) -Depth 100 -Compress
}

function Get-ContentHash($Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes((Get-CanonicalJson $Value))
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Test-JsonEqual($Left, $Right) {
    return [System.Text.Json.Nodes.JsonNode]::DeepEquals(
        [System.Text.Json.Nodes.JsonNode]::Parse((Get-CanonicalJson $Left)),
        [System.Text.Json.Nodes.JsonNode]::Parse((Get-CanonicalJson $Right)))
}

$configuration = Get-Content (Join-Path $ConfigurationDirectory 'evaluation.json') -Raw | ConvertFrom-Json -AsHashtable
$definitions = Get-Content (Join-Path $ConfigurationDirectory 'evaluators.json') -Raw | ConvertFrom-Json -AsHashtable
if ([string]::IsNullOrWhiteSpace($configuration.EvaluationName) -or [string]::IsNullOrWhiteSpace($configuration.ModelDeploymentName)) {
    throw 'EvaluationName and ModelDeploymentName are required in infra/foundry/evaluation.json.'
}
foreach ($setting in @('QualityPassThreshold', 'CommunicationPassThreshold', 'SafetySeverityThreshold')) {
    $minimum = if ($setting -eq 'SafetySeverityThreshold') { 0 } else { 1 }
    $maximum = if ($setting -eq 'SafetySeverityThreshold') { 7 } else { 5 }
    if ($configuration[$setting] -isnot [long] -and $configuration[$setting] -isnot [int] -or
        $configuration[$setting] -lt $minimum -or $configuration[$setting] -gt $maximum) {
        throw "Invalid $setting; expected an integer between $minimum and $maximum."
    }
}
if ($configuration.Evaluators -isnot [array] -or $configuration.Evaluators.Count -eq 0 -or
    @($configuration.Evaluators | Select-Object -Unique).Count -ne $configuration.Evaluators.Count) {
    throw 'Evaluators must be a nonempty array of unique names.'
}

$customEvaluators = [Collections.Generic.List[object]]::new()
$criteria = @(
    foreach ($name in $configuration.Evaluators) {
        $catalogName = $name
        if ($definitions.Contains($name)) {
            $entry = $definitions[$name]
            if ($entry.source_file -notmatch '^[a-z0-9_]+\.(py|txt)$') {
                throw "Invalid source file for evaluator '$name'."
            }
            $source = [IO.File]::ReadAllText((Join-Path $ConfigurationDirectory $entry.source_file)).Replace("`r`n", "`n")
            if ([string]::IsNullOrWhiteSpace($source)) {
                throw "Evaluator '$name' has an empty source file."
            }
            $definition = $entry.evaluator.definition
            $sourceProperty = switch ($definition.type) {
                'code' { 'code_text' }
                'prompt' { 'prompt_text' }
                default { throw "Unsupported evaluator definition type for '$name'." }
            }
            $definition[$sourceProperty] = $source
            $catalogName = '{0}_{1}' -f $name, (Get-ContentHash $definition).Substring(0, 12)
            $customEvaluators.Add(@{ name = $catalogName; evaluator = $entry.evaluator })
        }
        elseif ($name -notin @('builtin.relevance', 'builtin.coherence', 'builtin.fluency', 'builtin.violence')) {
            throw "Unsupported evaluator '$name'."
        }

        $mapping = @{ response = '{{item.response}}' }
        if ($name -notin @('builtin.fluency', 'official_microsoft_links')) {
            $mapping.query = '{{item.query}}'
        }
        $parameters = @{}
        if ($name -eq 'builtin.violence') {
            $parameters.threshold = $configuration.SafetySeverityThreshold
        }
        else {
            $parameters.deployment_name = $configuration.ModelDeploymentName
            if ($name -eq 'official_microsoft_links') {
                $parameters.pass_threshold = 1
            }
            else {
                $parameters.threshold = if ($name -eq 'corporate_communication') {
                    $configuration.CommunicationPassThreshold
                }
                else {
                    $configuration.QualityPassThreshold
                }
            }
        }
        @{
            type = 'azure_ai_evaluator'
            name = $name -replace '^builtin\.', ''
            evaluator_name = $catalogName
            data_mapping = $mapping
            initialization_parameters = $parameters
        }
    }
)
$request = @{
    name = $configuration.EvaluationName
    data_source_config = @{ type = 'azure_ai_source'; scenario = 'traces' }
    testing_criteria = $criteria
    metadata = @{ configuration_hash = (Get-ContentHash @{ scenario = 'traces'; testing_criteria = $criteria }) }
}

if ($ValidateOnly) {
    return @{ CustomEvaluators = $customEvaluators.ToArray(); Evaluation = $request }
}
if ([string]::IsNullOrWhiteSpace($Environment)) {
    throw 'AZURE_ENV_NAME must be set, or pass -Environment. Run this script through azd postprovision.'
}
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$endpointOutput = azd env get-value FOUNDRY_PROJECT_ENDPOINT --environment $Environment --cwd $repositoryRoot
if ($LASTEXITCODE -ne 0) {
    throw 'Cannot read FOUNDRY_PROJECT_ENDPOINT from the azd environment.'
}
$projectEndpoint = ([string] $endpointOutput).Trim().TrimEnd('/')
$projectUri = [Uri] $projectEndpoint
if (-not $projectUri.IsAbsoluteUri -or $projectUri.Scheme -ne 'https' -or
    -not $projectUri.Host.EndsWith('.services.ai.azure.com', [StringComparison]::OrdinalIgnoreCase) -or
    $projectUri.AbsolutePath -notmatch '^/api/projects/[^/]+$') {
    throw 'FOUNDRY_PROJECT_ENDPOINT must be an HTTPS Microsoft Foundry project endpoint.'
}

function Invoke-FoundryRequest([string] $Method, [string] $Url, $Body = $null) {
    $requestUri = [Uri] $Url
    if ($requestUri.Scheme -ne $projectUri.Scheme -or $requestUri.Authority -ne $projectUri.Authority -or
        -not $requestUri.AbsolutePath.StartsWith($projectUri.AbsolutePath + '/', [StringComparison]::Ordinal)) {
        throw 'Foundry returned a continuation URL outside the selected project.'
    }
    $cliUrl = if ($IsWindows -and (Get-Command az).Source -match '\.(cmd|bat)$') { '"' + $Url + '"' } else { $Url }
    $arguments = @('rest', '--method', $Method, '--url', $cliUrl, '--resource', 'https://ai.azure.com', '--output', 'json', '--only-show-errors')
    $arguments += @('--headers', 'Foundry-Features=Evaluations=V1Preview', 'Content-Type=application/json')
    $bodyFile = $null
    try {
        if ($null -ne $Body) {
            $bodyFile = [IO.Path]::GetTempFileName()
            [IO.File]::WriteAllText($bodyFile, (Get-CanonicalJson $Body), [Text.UTF8Encoding]::new($false))
            $arguments += @('--body', "@$bodyFile")
        }
        $output = & az @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Foundry $Method failed. Check Azure CLI authentication, project readiness and deployment identity permissions."
        }
        return ($output -join "`n") | ConvertFrom-Json -AsHashtable
    }
    finally {
        if ($bodyFile) {
            [IO.File]::Delete($bodyFile)
        }
    }
}

$existingEvaluators = @{}
$nextPage = "$projectEndpoint/evaluators?api-version=v1&type=custom&limit=100"
$visitedPages = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
while ($nextPage) {
    if (-not $visitedPages.Add($nextPage)) {
        throw 'Foundry evaluator pagination did not advance.'
    }
    $page = Invoke-FoundryRequest 'get' $nextPage
    foreach ($existing in $page.value) {
        $existingEvaluators[$existing.name] = $existing
    }
    $nextPage = if ($page['nextLink']) { [Uri]::new([Uri] $nextPage, [string] $page.nextLink).AbsoluteUri } else { $null }
}
foreach ($custom in $customEvaluators) {
    if ($existingEvaluators.ContainsKey($custom.name)) {
        $existingDefinition = $existingEvaluators[$custom.name].definition.Clone()
        $inactiveSource = if ($custom.evaluator.definition.type -eq 'code') { 'prompt_text' } else { 'code_text' }
        if ($existingDefinition.Contains($inactiveSource) -and $existingDefinition[$inactiveSource] -ceq '') {
            $existingDefinition.Remove($inactiveSource)
        }
        if (-not (Test-JsonEqual $existingDefinition $custom.evaluator.definition)) {
            throw "Custom evaluator '$($custom.name)' exists with a different definition."
        }
        Write-Host "Reusing Foundry custom evaluator '$($custom.name)'."
    }
    else {
        $url = '{0}/evaluators/{1}/versions?api-version=v1' -f $projectEndpoint, [Uri]::EscapeDataString($custom.name)
        $registered = Invoke-FoundryRequest 'post' $url $custom.evaluator
        if ($registered.name -cne $custom.name -or [string]::IsNullOrWhiteSpace($registered.version)) {
            throw 'Foundry did not return the published evaluator name and version.'
        }
        Write-Host "Published Foundry custom evaluator '$($custom.name)', version '$($registered.version)'."
    }
}

$evaluationId = $null
$after = $null
$visitedCursors = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
do {
    $url = "$projectEndpoint/openai/v1/evals?limit=100&order=asc&order_by=created_at"
    if ($after) { $url += '&after=' + [Uri]::EscapeDataString($after) }
    $page = Invoke-FoundryRequest 'get' $url
    foreach ($existing in $page.data) {
        if ($existing.name -ceq $request.name -and $existing['metadata'] -is [Collections.IDictionary] -and
            $existing.metadata['configuration_hash'] -ceq $request.metadata.configuration_hash) {
            $existingCriteria = @(
                foreach ($criterion in $existing.testing_criteria) {
                    $comparable = $criterion.Clone()
                    $comparable.Remove('id')
                    if ($comparable.Contains('evaluator_version') -and $comparable.evaluator_version -ceq '') {
                        $comparable.Remove('evaluator_version')
                    }
                    $comparable
                }
            )
            if (-not (Test-JsonEqual $existingCriteria $criteria)) {
                throw 'The matching Foundry evaluation group has different testing criteria.'
            }
            $evaluationId = $existing.id
            break
        }
    }
    if ($evaluationId -or -not $page['has_more']) { break }
    $after = [string] $page['last_id']
    if ([string]::IsNullOrWhiteSpace($after) -or -not $visitedCursors.Add($after)) {
        throw 'Foundry evaluation pagination did not advance.'
    }
} while ($true)
if (-not $evaluationId) {
    $created = Invoke-FoundryRequest 'post' "$projectEndpoint/openai/v1/evals" $request
    $evaluationId = $created.id
    Write-Host "Created Foundry evaluation group '$($request.name)' ($evaluationId)."
}
else {
    Write-Host "Reusing Foundry evaluation group '$($request.name)' ($evaluationId)."
}
if ($evaluationId -notmatch '^eval_[a-zA-Z0-9_-]+$') {
    throw 'Foundry did not return a valid evaluation group ID.'
}
azd env set FOUNDRY_EVALUATION_ID $evaluationId --environment $Environment --cwd $repositoryRoot
if ($LASTEXITCODE -ne 0) {
    throw 'Cannot save FOUNDRY_EVALUATION_ID to the azd environment.'
}
Write-Host 'Foundry evaluation provisioning completed. No agent requests or evaluation runs were submitted.'
