<#
.SYNOPSIS
    Generates real multi-turn conversations with the deployed demo agent.
.DESCRIPTION
    Uses azd's saved Responses conversation between turns and starts a new
    conversation for each scenario. Waits between live requests to reduce rate
    limiting. DryRun does not wait or call azd or Azure.
.EXAMPLE
    ./scripts/Invoke-DemoConversations.ps1 -Environment <name-of-environment> -ConversationCount 6 -DryRun
.NOTES
    Follow-up and confidence rule: ../.github/instructions/wow-follow-up-question.instructions.md.
    Live execution incurs usage charges and updates azd's saved conversation.
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $Environment,

    [ValidateRange(1, 1000)]
    [int] $ConversationCount = 6,

    [ValidateSet('en', 'es', 'mixed')]
    [string] $Language = 'en',

    [ValidateRange(1, 3600)]
    [int] $TimeoutSeconds = 300,

    [ValidateRange(0, 3600)]
    [int] $DelaySeconds = 10,

    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$catalog = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'demo-conversations.json') -Raw | ConvertFrom-Json)
$scenarios = @($catalog | Where-Object { $Language -eq 'mixed' -or $_.language -eq $Language })

if ($scenarios.Count -eq 0) {
    throw "No scenarios found for language '$Language'."
}

foreach ($scenario in $scenarios) {
    if ([string]::IsNullOrWhiteSpace($scenario.name) -or @($scenario.turns).Count -eq 0) {
        throw 'Every scenario must have a name and at least one turn.'
    }
    foreach ($prompt in $scenario.turns) {
        if ($prompt -isnot [string] -or [string]::IsNullOrWhiteSpace($prompt)) {
            throw "Scenario '$($scenario.name)' contains an invalid prompt."
        }
    }
}

if (-not $DryRun) {
    if (-not (Get-Command azd -ErrorAction SilentlyContinue)) {
        throw 'Azure Developer CLI (azd) is required. See demo.es.md for setup.'
    }
    $invokeHelp = (& azd ai agent invoke --help 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $invokeHelp -notmatch '--new-conversation') {
        throw 'The installed azd agent extension must support --new-conversation. See demo.es.md.'
    }
    Write-Host 'LIVE RUN: model calls and automatic evaluations can incur charges. Press Ctrl+C to stop.'
    Write-Host 'Do not invoke this agent from another CLI process while this script runs.'
}

$sentTurns = 0
$startedAt = [DateTime]::UtcNow.ToString('o')
Write-Host "Start UTC: $startedAt | Environment: $Environment | Conversations: $ConversationCount | Language: $Language | Delay seconds: $DelaySeconds | Dry run: $DryRun"

for ($conversationIndex = 0; $conversationIndex -lt $ConversationCount; $conversationIndex++) {
    $scenario = $scenarios[$conversationIndex % $scenarios.Count]
    Write-Host "Conversation $($conversationIndex + 1)/${ConversationCount}: $($scenario.name)"

    for ($turnIndex = 0; $turnIndex -lt $scenario.turns.Count; $turnIndex++) {
        $prompt = $scenario.turns[$turnIndex]
        $invokeArguments = @(
            'ai', 'agent', 'invoke', 'agent-autoevaluations', $prompt,
            '--cwd', $repositoryRoot,
            '--environment', $Environment,
            '--protocol', 'responses',
            '--timeout', $TimeoutSeconds.ToString(),
            '--output', 'raw',
            '--no-prompt'
        )
        if ($turnIndex -eq 0) {
            $invokeArguments += '--new-conversation'
        }

        Write-Host "  Turn $($turnIndex + 1)/$($scenario.turns.Count): $prompt"
        if (-not $DryRun) {
            if ($sentTurns -gt 0 -and $DelaySeconds -gt 0) {
                Write-Host "Waiting $DelaySeconds seconds before the next request."
                Start-Sleep -Seconds $DelaySeconds
            }
            $rawResponse = @(& azd @invokeArguments)
            if ($LASTEXITCODE -ne 0) {
                throw "Invocation failed at conversation $($conversationIndex + 1), turn $($turnIndex + 1). Stopped without retry; $sentTurns previous turns succeeded. Check azd authentication, agent status, permissions and quota."
            }
            $completedResponses = @(foreach ($line in $rawResponse) {
                if ($line.StartsWith('data: ') -and $line -ne 'data: [DONE]') {
                    $event = $line.Substring(6) | ConvertFrom-Json
                    if ($event.type -eq 'response.completed') {
                        $event.response
                    }
                }
            })
            $response = $completedResponses | Select-Object -Last 1
            $responseText = @($response.output | Where-Object { $_.type -eq 'message' -and $_.role -eq 'assistant' } | ForEach-Object {
                $_.content | Where-Object type -eq 'output_text' | ForEach-Object text
            }) -join "`n"
            if ($response.status -ne 'completed' -or [string]::IsNullOrWhiteSpace($responseText)) {
                throw "No completed text response at conversation $($conversationIndex + 1), turn $($turnIndex + 1). Stopped without retry; $sentTurns previous turns succeeded. Inspect the agent and its Responses stream."
            }
            Write-Host $responseText
        }
        $sentTurns++
    }
}

Write-Host "End UTC: $([DateTime]::UtcNow.ToString('o'))"
if ($DryRun) {
    Write-Host "Dry run complete: $ConversationCount conversations, $sentTurns planned requests. No Azure calls were made."
}
else {
    Write-Host "Completed: $ConversationCount conversations, $sentTurns successful CLI requests. Verify trace ingestion and evaluation results separately."
}
