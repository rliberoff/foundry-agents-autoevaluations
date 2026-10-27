using System.ComponentModel.DataAnnotations;

namespace Foundry.Agents.Autoevaluation.Demo.Options;

/// <summary>
/// Options for configuring the Foundry continuous evaluation background service.
/// </summary>
public sealed class FoundryContinuousEvaluationOptions
{
    /// <summary>
    /// Gets a value indicating whether the Foundry continuous evaluation service is enabled. Default is false.
    /// </summary>
    public bool IsEnabled { get; init; }

    /// <summary>
    /// Gets the ID of the evaluation group created during azd provisioning.
    /// </summary>
    public string EvaluationId { get; init; } = string.Empty;

    /// <summary>
    /// Gets the interval in seconds between evaluation result checks.
    /// </summary>
    [Range(1, 300)]
    public int ResultPollingIntervalSeconds { get; init; } = 10;

    /// <summary>
    /// Gets the maximum local wait for results without canceling the remote run.
    /// </summary>
    [Range(1, 60)]
    public int ResultTimeoutMinutes { get; init; } = 10;

    /// <summary>
    /// Gets the number of minutes to look back when evaluating traces. Default is 60 minutes. Maximum is 10080 minutes (7 days).
    /// </summary>
    [Range(1, 10080)]
    public int LookbackMinutes { get; init; } = 60;

    /// <summary>
    /// Gets an optional override for the polling interval between evaluation runs in minutes.
    /// When <see langword="null"/> , the interval matches <see cref="LookbackMinutes"/>.
    /// </summary>
    [Range(1, int.MaxValue)]
    public int? PollingIntervalMinutes { get; init; }

    /// <summary>
    /// Gets the maximum number of traces to evaluate per run. Default is 50 traces.
    /// </summary>
    [Range(1, int.MaxValue)]
    public int MaxTracesPerRun { get; init; } = 50;

    /// <summary>
    /// Gets the percentage of the trace cap to request. This is not a probability-based sampling rate. Zero skips runs.
    /// </summary>
    [Range(0, 100)]
    public int TraceSamplingPercentage { get; init; } = 100;
}
