<#
.SYNOPSIS
    Downloads the Microsoft Teams / Microsoft 365 app package generated and validated by Microsoft Foundry for a hosted agent.

.DESCRIPTION
    Calls `POST {project}/agents/{agent}/microsoft365/zip`, which builds the same validated package (`manifest.json`,
    `color.png`, `outline.png`) as the portal "Publish to Teams" flow, without submitting it to the agent catalog.
    Upload the resulting ZIP in Teams via Apps > Manage your apps > Upload an app.

    Defaults are read from the selected azd environment (`azd env get-value`).

    Reference: https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot-virtual-network#download-and-inspect-the-app-package

.EXAMPLE
    ./scripts/Get-TeamsAppPackage.ps1 -Environment relv -DeveloperName 'Rodrigo Liberoff' `
        -DeveloperWebsiteUrl 'https://github.com/rliberoff' -PrivacyUrl 'https://privacy.microsoft.com' `
        -TermsOfUseUrl 'https://www.microsoft.com/legal/terms-of-use'
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Environment,

    [Parameter(Mandatory)]
    [ValidateLength(1, 32)]
    [string] $DeveloperName,

    [Parameter(Mandatory)]
    [ValidatePattern('^https://')]
    [string] $DeveloperWebsiteUrl,

    [Parameter(Mandatory)]
    [ValidatePattern('^https://')]
    [string] $PrivacyUrl,

    [Parameter(Mandatory)]
    [ValidatePattern('^https://')]
    [string] $TermsOfUseUrl,

    [string] $AgentDisplayName = 'Dereck',

    [ValidatePattern('^[1-9]\d*\.\d+\.\d+$')]
    [string] $AppVersion = '1.0.0',

    [ValidateSet('Shared', 'Tenant')]
    [string] $PublishScope = 'Shared',

    [ValidateLength(1, 80)]
    [string] $ShortDescription = 'Agent Framework demo for production-trace-based autoevaluations.',

    [ValidateLength(1, 4000)]
    [string] $FullDescription = 'Microsoft Agent Framework hosted agent on Microsoft Foundry used to demo production-trace-based autoevaluations.',

    [string] $BotServiceArmId,

    [string] $OutputPath = (Join-Path $PWD 'appPackage.zip')
)

$ErrorActionPreference = 'Stop'

function Get-AzdValue([string] $Name) {
    $value = azd env get-value $Name -e $Environment 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($value)) {
        throw "Value '$Name' not found in azd environment '$Environment'."
    }
    return $value.Trim()
}

$projectEndpoint = (Get-AzdValue 'AZURE_AI_PROJECT_ENDPOINT').TrimEnd('/')
$agentName = Get-AzdValue 'AGENT_AGENT_AUTOEVALUATIONS_NAME'
$agentClientId = Get-AzdValue 'AGENT_AGENT_AUTOEVALUATIONS_INSTANCE_IDENTITY_CLIENT_ID'
$resourceGroup = Get-AzdValue 'AZURE_RESOURCE_GROUP'

if (-not $BotServiceArmId) {
    # The Activity protocol only accepts the bot whose App ID is the agent's instance identity.
    $botIds = az resource list --resource-group $resourceGroup --resource-type 'Microsoft.BotService/botServices' --query '[].id' --output tsv
    $BotServiceArmId = $botIds | Where-Object {
        $_ -and (az resource show --ids $_ --query 'properties.msaAppId' --output tsv) -eq $agentClientId
    } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($BotServiceArmId)) {
        throw "No Azure Bot Service with msaAppId '$agentClientId' found in '$resourceGroup'. Publish the agent to Teams once from the Foundry portal, or pass -BotServiceArmId."
    }
}

$token = az account get-access-token --resource 'https://ai.azure.com' --query accessToken --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'Unable to get an access token for https://ai.azure.com. Run `az login` first.'
}

$body = [ordered]@{
    agentDisplayName    = $AgentDisplayName
    botServiceArmId     = $BotServiceArmId.Trim()
    publishScope        = $PublishScope
    publishAsAutopilot  = $false
    appVersion          = $AppVersion
    shortDescription    = $ShortDescription
    fullDescription     = $FullDescription
    developerName       = $DeveloperName
    developerWebsiteUrl = $DeveloperWebsiteUrl
    privacyUrl          = $PrivacyUrl
    termsOfUseUrl       = $TermsOfUseUrl
} | ConvertTo-Json

$uri = "$projectEndpoint/agents/$agentName/microsoft365/zip?api-version=v1"
Write-Host "Requesting Teams app package for agent '$agentName' (scope: $PublishScope)..."

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$response = Invoke-WebRequest -Uri $uri -Method Post -Body $body -ContentType 'application/json' `
    -Headers @{ Authorization = "Bearer $token" } -SkipHttpErrorCheck

if ($response.StatusCode -ne 200) {
    throw "Package generation failed with HTTP $($response.StatusCode): $($response.Content)"
}

[System.IO.File]::WriteAllBytes($OutputPath, $response.RawContentStream.ToArray())

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($OutputPath)
try {
    $entry = $zip.Entries | Where-Object FullName -EQ 'manifest.json'
    if (-not $entry) {
        throw "The downloaded package doesn't contain manifest.json."
    }
    $reader = [System.IO.StreamReader]::new($entry.Open())
    $manifest = $reader.ReadToEnd() | ConvertFrom-Json
    $reader.Dispose()

    Write-Host "Package saved to: $OutputPath"
    Write-Host "  Files:   $(($zip.Entries.FullName) -join ', ')"
    Write-Host "  Name:    $($manifest.name.short)"
    Write-Host "  Version: $($manifest.version)"
    Write-Host "  Bot ID:  $($manifest.bots[0].botId)"
}
finally {
    $zip.Dispose()
}

Write-Host 'Upload it in Teams: Apps > Manage your apps > Upload an app > Upload a custom app.'
