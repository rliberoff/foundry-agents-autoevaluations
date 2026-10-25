#pragma warning disable OPENAI001 // OpenAI.Evals.EvaluationClient is experimental
#pragma warning disable AAIP001 // The evaluator catalog is experimental in the installed SDK.

using System.ClientModel;
using System.ClientModel.Primitives;
using System.Text.Json;

using Azure.AI.Projects;
using Azure.AI.Projects.Evaluation;
using Azure.Identity;

using Foundry.Agents.Autoevaluation.Demo.Options;

using Microsoft.Extensions.Options;

using OpenAI.Evals;

namespace Foundry.Agents.Autoevaluation.Demo.Services;

/// <summary>
/// A hosted background service that configures Foundry evaluators and periodically evaluates
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
        string? evaluationId = null;

        // First evaluation run is triggered after the initial polling interval to allow traces to accumulate.
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(options.PollingIntervalMinutes ?? (options.LookbackHours * 60)));
        await timer.WaitForNextTickAsync(stoppingToken);

        do
        {
            evaluationId ??= await EnsureEvaluationAsync(projectClient, evaluationClient, stoppingToken);
            if (evaluationId is not null)
            {
                await TriggerEvaluationRunAsync(evaluationClient, evaluationId, stoppingToken);
            }
        }
        while (await timer.WaitForNextTickAsync(stoppingToken));
    }

    private async Task<string?> EnsureEvaluationAsync(AIProjectClient projectClient, EvaluationClient evaluationClient, CancellationToken cancellationToken)
    {
        var request = FoundryEvaluationConfiguration.CreateRequest(options);
        var configurationHash = request.Metadata[@"configuration_hash"];

        try
        {
            await EnsureCustomEvaluatorsAsync(projectClient, cancellationToken);
            var existingEvaluationId = await FindExistingEvaluationIdAsync(evaluationClient, configurationHash, cancellationToken);
            if (existingEvaluationId is not null)
            {
                LogEvaluationAlreadyExists(logger, options.EvaluationName, existingEvaluationId);
                return existingEvaluationId;
            }

            using var content = BinaryContent.Create(BinaryData.FromObjectAsJson(request));
            var requestOptions = new RequestOptions { CancellationToken = cancellationToken };
            var result = await evaluationClient.CreateEvaluationAsync(content, requestOptions);
            using var doc = JsonDocument.Parse(result.GetRawResponse().Content.ToMemory());
            var id = doc.RootElement.GetProperty(@"id").GetString();
            if (string.IsNullOrWhiteSpace(id))
            {
                throw new InvalidOperationException(@"Foundry did not return an evaluation ID.");
            }

            LogEvaluationCreated(logger, id);
            return id;
        }
        catch (ClientResultException ex) when (ex.Status == 409)
        {
            var conflictEvaluationId = await FindExistingEvaluationIdAsync(evaluationClient, configurationHash, cancellationToken);
            if (conflictEvaluationId is not null)
            {
                return conflictEvaluationId;
            }

            LogEvaluationConflictResolutionFailed(logger, ex, options.EvaluationName);
            return null;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            LogEvaluationCreateFailed(logger, ex);
            return null;
        }
    }

    private async Task EnsureCustomEvaluatorsAsync(AIProjectClient projectClient, CancellationToken cancellationToken)
    {
        var definitions = new Dictionary<string, EvaluatorVersion>(StringComparer.Ordinal);
        foreach (var name in options.Evaluators)
        {
            var definition = FoundryEvaluationConfiguration.CreateCustomEvaluator(name);
            if (definition is not null)
            {
                definitions.Add(FoundryEvaluationConfiguration.GetCatalogName(name, definition), definition);
            }
        }

        if (definitions.Count == 0)
        {
            return;
        }

        await foreach (var existing in projectClient.Evaluators.GetLatestVersionsAsync(type: ListVersionsRequestType.Custom, cancellationToken: cancellationToken))
        {
            if (definitions.TryGetValue(existing.Name, out var expected))
            {
                using var existingDocument = JsonDocument.Parse(ModelReaderWriter.Write(existing.Definition).ToMemory());
                using var expectedDocument = JsonDocument.Parse(ModelReaderWriter.Write(expected.Definition).ToMemory());
                if (!JsonElement.DeepEquals(existingDocument.RootElement, expectedDocument.RootElement))
                {
                    throw new InvalidOperationException($@"Custom evaluator '{existing.Name}' exists with a different definition.");
                }

                definitions.Remove(existing.Name);
            }
        }

        foreach (var (name, definition) in definitions)
        {
            EvaluatorVersion registered = await projectClient.Evaluators.CreateVersionAsync(name, definition, cancellationToken);
            LogCustomEvaluatorRegistered(logger, name, registered.Version);
        }
    }

    private async Task<string?> FindExistingEvaluationIdAsync(EvaluationClient evaluationClient, string configurationHash, CancellationToken cancellationToken)
    {
        string? after = null;

        while (true)
        {
            var requestOptions = new RequestOptions { CancellationToken = cancellationToken };
            var result = await evaluationClient.GetEvaluationsAsync(limit: 100, orderBy: "created_at", order: "asc", after: after, options: requestOptions);
            using var doc = JsonDocument.Parse(result.GetRawResponse().Content.ToMemory());
            var root = doc.RootElement;

            if (root.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Array)
            {
                foreach (var evaluation in data.EnumerateArray())
                {
                    var id = GetMatchingEvaluationId(evaluation, configurationHash);
                    if (id is not null)
                    {
                        return id;
                    }
                }
            }

            var hasMore = root.TryGetProperty(@"has_more", out var hasMoreProperty) && hasMoreProperty.GetBoolean();

            // Stop when there are no more pages or the cursor cannot advance.
            if (!hasMore
                || !root.TryGetProperty(@"last_id", out var lastIdProperty)
                || lastIdProperty.ValueKind != JsonValueKind.String
                || string.IsNullOrWhiteSpace(lastIdProperty.GetString())
                || string.Equals(after, lastIdProperty.GetString(), StringComparison.Ordinal))
            {
                return null;
            }

            after = lastIdProperty.GetString();
        }
    }

    private string? GetMatchingEvaluationId(JsonElement evaluation, string configurationHash)
    {
        // The same name may be used by evaluations with different evaluator configurations.
        // Check each JSON type before reading its value; missing or invalid fields do not match.
        return evaluation.TryGetProperty(@"name", out var name)
            && name.ValueKind == JsonValueKind.String
            && string.Equals(name.GetString(), options.EvaluationName, StringComparison.OrdinalIgnoreCase)
            && evaluation.TryGetProperty(@"metadata", out var metadata)
            && metadata.ValueKind == JsonValueKind.Object
            && metadata.TryGetProperty(@"configuration_hash", out var hash)
            && hash.ValueKind == JsonValueKind.String
            && string.Equals(hash.GetString(), configurationHash, StringComparison.OrdinalIgnoreCase)
            && evaluation.TryGetProperty("id", out var id)
            && id.ValueKind == JsonValueKind.String
            && !string.IsNullOrWhiteSpace(id.GetString())
                ? id.GetString()
                : null;
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

    [LoggerMessage(Level = LogLevel.Information, Message = @"Foundry custom evaluator '{EvaluatorName}' registered at version '{Version}'.")]
    private static partial void LogCustomEvaluatorRegistered(ILogger logger, string evaluatorName, string version);

    [LoggerMessage(Level = LogLevel.Information, Message = @"Foundry evaluation group '{EvaluationName}' created successfully.")]
    private static partial void LogEvaluationCreated(ILogger logger, string evaluationName);

    [LoggerMessage(Level = LogLevel.Information, Message = @"Reusing Foundry evaluation group '{EvaluationName}' ({EvaluationId}) with matching evaluator configuration.")]
    private static partial void LogEvaluationAlreadyExists(ILogger logger, string evaluationName, string evaluationId);

    [LoggerMessage(Level = LogLevel.Error, Message = @"Foundry reported a conflict for evaluation group '{EvaluationName}', but no matching configuration could be found.")]
    private static partial void LogEvaluationConflictResolutionFailed(ILogger logger, Exception exception, string evaluationName);

    [LoggerMessage(Level = LogLevel.Error, Message = @"Failed to configure Foundry trace evaluation. Setup will be retried at the next interval.")]
    private static partial void LogEvaluationCreateFailed(ILogger logger, Exception exception);

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

#pragma warning restore AAIP001 // The evaluator catalog is experimental in the installed SDK.
#pragma warning restore OPENAI001 // OpenAI.Evals.EvaluationClient is experimental
