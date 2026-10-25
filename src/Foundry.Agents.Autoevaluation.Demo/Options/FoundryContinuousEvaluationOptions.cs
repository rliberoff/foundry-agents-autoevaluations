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
    /// Gets the name of the evaluation.
    /// </summary>
    [Required]
    public required string EvaluationName { get; init; }

    /// <summary>
    /// Gets or sets the name of the model (LLM) used for evaluation.
    /// </summary>
    [Required]
    public required string ModelDeploymentName { get; set; }

    /// <summary>
    /// Gets the minimum passing quality score on the one-to-five scale.
    /// </summary>
    [Range(1, 5)]
    public int QualityPassThreshold { get; init; } = 3;

    /// <summary>
    /// Gets the minimum passing corporate communication score.
    /// </summary>
    [Range(1, 5)]
    public int CommunicationPassThreshold { get; init; } = 4;

    /// <summary>
    /// Gets the maximum passing violence severity on the zero-to-seven scale.
    /// </summary>
    [Range(0, 7)]
    public int SafetySeverityThreshold { get; init; } = 3;

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
    /// Gets the number of hours to look back when evaluating traces. Default is 1 hour. Maximum is 168 hours (7 days).
    /// </summary>
    [Range(1, 168)]
    public int LookbackHours { get; init; } = 1;

    /// <summary>
    /// Gets an optional override for the polling interval between evaluation runs in minutes.
    /// When <see langword="null"/> , the interval matches <see cref="LookbackHours"/>.
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

    /// <summary>
    /// Gets the list of evaluators to use for the evaluation.
    /// </summary>
    [Required]
    [MinLength(1)]
    public required IList<string> Evaluators { get; init; } = [];
}
