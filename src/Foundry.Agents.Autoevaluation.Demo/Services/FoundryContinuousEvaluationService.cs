#pragma warning disable OPENAI001 // OpenAI.Evals.EvaluationClient is experimental

using System.ClientModel;
using System.ClientModel.Primitives;
using System.Text.Json;

using Azure.AI.Projects;
using Azure.Identity;

using Foundry.Agents.Autoevaluation.Demo.Options;

using Microsoft.Extensions.Options;

using OpenAI.Evals;

namespace Foundry.Agents.Autoevaluation.Demo.Services;

/// <summary>
/// A hosted background service that periodically evaluates traces using a provisioned evaluation group and
/// agent traces already captured in Application Insights, without replaying user requests.
/// </summary>
internal sealed partial class FoundryContinuousEvaluationService : BackgroundService
{
    private readonly string agentName;
    private readonly Uri foundryProjectEndpoint;
    private readonly ILogger<FoundryContinuousEvaluationService> logger;

    private readonly FoundryContinuousEvaluationOptions options;

    /// <summary>
    /// Initializes a new instance of the <see cref="FoundryContinuousEvaluationService"/> class.
    /// </summary>
    /// <param name="agentId">The ID of the agent whose traces will be evaluated.</param>
    /// <param name="agentName">The name of the agent whose traces will be evaluated.</param>
    /// <param name="foundryProjectEndpoint">The endpoint of the Foundry project.</param>
    /// <param name="optionsMonitor">The monitor for the Foundry continuous evaluation options.</param>
    /// <param name="logger">The logger for this service.</param>
    public FoundryContinuousEvaluationService(
        string agentId,
        string agentName,
        Uri foundryProjectEndpoint,
        IOptionsMonitor<FoundryContinuousEvaluationOptions> optionsMonitor,
        ILogger<FoundryContinuousEvaluationService> logger)
    {
        this.agentName = agentName;
        this.foundryProjectEndpoint = foundryProjectEndpoint;

        this.logger = logger;

        options = optionsMonitor.CurrentValue;
    }

    /// <inheritdoc/>
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!options.IsEnabled)
        {
            LogEvaluationDisabled(logger);
            return;
        }

        if (options.TraceSamplingPercentage == 0)
        {
            LogSamplingDisabled(logger);
            return;
        }

        var projectClient = new AIProjectClient(foundryProjectEndpoint, new DefaultAzureCredential());
        var evaluationClient = projectClient.ProjectOpenAIClient.GetEvaluationClient();
        var evaluationId = options.EvaluationId;

        // First evaluation run is triggered after the initial polling interval to allow traces to accumulate.
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(options.PollingIntervalMinutes ?? (options.LookbackHours * 60)));
        await timer.WaitForNextTickAsync(stoppingToken);

        do
        {
            await TriggerEvaluationRunAsync(evaluationClient, evaluationId, stoppingToken);
        }
        while (await timer.WaitForNextTickAsync(stoppingToken));
    }

    private async Task TriggerEvaluationRunAsync(EvaluationClient evaluationClient, string evaluationId, CancellationToken cancellationToken)
    {
        var request = FoundryEvaluationConfiguration.CreateRunRequest(options, agentName, evaluationId);
        var runName = request.Name;
        try
        {
            using var content = BinaryContent.Create(BinaryData.FromObjectAsJson(request));
            var result = await evaluationClient.CreateEvaluationRunAsync(evaluationId, content, new RequestOptions
            {
                CancellationToken = cancellationToken,
            });
            using var document = JsonDocument.Parse(result.GetRawResponse().Content.ToMemory());
            var runId = document.RootElement.GetProperty(@"id").GetString();
            if (string.IsNullOrWhiteSpace(runId))
            {
                throw new InvalidOperationException(@"Foundry did not return an evaluation run ID.");
            }

            LogEvaluationRunTriggered(logger, runName, evaluationId, agentName);
            await ReportEvaluationResultsAsync(evaluationClient, evaluationId, runId, cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            LogEvaluationRunFailed(logger, ex, runName);
        }
    }

    private async Task ReportEvaluationResultsAsync(EvaluationClient evaluationClient, string evaluationId, string runId, CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromMinutes(options.ResultTimeoutMinutes));

        try
        {
            while (true)
            {
                var result = await evaluationClient.GetEvaluationRunAsync(evaluationId, runId, new RequestOptions { CancellationToken = timeout.Token });
                using var document = JsonDocument.Parse(result.GetRawResponse().Content.ToMemory());
                var run = document.RootElement;
                var status = run.GetProperty(@"status").GetString();

                if (status is @"completed" or @"failed" or @"canceled")
                {
                    var reportUrl = run.TryGetProperty(@"report_url", out var report) ? report.GetString() : null;
                    LogEvaluationRunCompleted(logger, evaluationId, runId, status, reportUrl);

                    if (status == @"failed" && run.TryGetProperty(@"error", out var error))
                    {
                        throw new InvalidOperationException($@"Foundry evaluation run '{runId}' failed: {error}");
                    }

                    if (status == @"completed" && run.TryGetProperty(@"per_testing_criteria_results", out var criteria) && criteria.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var criterion in criteria.EnumerateArray())
                        {
                            var passed = criterion.GetProperty(@"passed").GetInt32();
                            var failed = criterion.GetProperty(@"failed").GetInt32();
                            LogEvaluationMetric(logger, runId, criterion.GetProperty(@"testing_criteria").GetString(), passed, failed);
                        }
                    }

                    return;
                }

                await Task.Delay(TimeSpan.FromSeconds(options.ResultPollingIntervalSeconds), timeout.Token);
            }
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            LogEvaluationResultsPending(logger, evaluationId, runId);
        }
    }

    // Logger messages are grouped at the end of the class to avoid cluttering the main logic with logging details.

    [System.Diagnostics.CodeAnalysis.SuppressMessage(@"Style", @"SA1204:StaticElementsMustAppearBeforeInstanceElements", Justification = @"Logger messages grouped at end of class.")]
    [LoggerMessage(Level = LogLevel.Information, Message = @"Foundry trace evaluation is disabled.")]
    private static partial void LogEvaluationDisabled(ILogger logger);

    [LoggerMessage(Level = LogLevel.Information, Message = @"TraceSamplingPercentage is zero; no Foundry evaluation runs will be created.")]
    private static partial void LogSamplingDisabled(ILogger logger);

    [LoggerMessage(Level = LogLevel.Information, Message = @"Triggered Foundry trace evaluation run '{RunName}' under group '{EvaluationId}' for agent '{AgentName}'.")]
    private static partial void LogEvaluationRunTriggered(ILogger logger, string runName, string evaluationId, string agentName);

    [LoggerMessage(Level = LogLevel.Warning, Message = @"Failed to trigger Foundry evaluation run '{RunName}'. It will be retried on the next scheduled interval.")]
    private static partial void LogEvaluationRunFailed(ILogger logger, Exception exception, string runName);

    [LoggerMessage(Level = LogLevel.Information, Message = @"Foundry evaluation '{EvaluationId}', run '{RunId}' reached status '{Status}'. Report: {ReportUrl}")]
    private static partial void LogEvaluationRunCompleted(ILogger logger, string evaluationId, string runId, string? status, string? reportUrl);

    [LoggerMessage(Level = LogLevel.Information, Message = @"Foundry evaluation run '{RunId}', evaluator '{EvaluatorName}': {Passed} passed, {Failed} failed.")]
    private static partial void LogEvaluationMetric(ILogger logger, string runId, string? evaluatorName, int passed, int failed);

    [LoggerMessage(Level = LogLevel.Warning, Message = @"Foundry evaluation '{EvaluationId}', run '{RunId}' is still pending. Review it in Foundry; the remote run has not been canceled.")]
    private static partial void LogEvaluationResultsPending(ILogger logger, string evaluationId, string runId);
}

#pragma warning restore OPENAI001 // OpenAI.Evals.EvaluationClient is experimental
