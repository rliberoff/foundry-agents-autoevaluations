using System.Text.Json.Serialization;

namespace Foundry.Agents.Autoevaluation.Demo.Models;

/// <summary>
/// Selects captured traces by deployed agent name instead of an in-memory framework ID.
/// </summary>
internal sealed class FoundryEvaluationTraceSource
{
    /// <summary>
    /// Gets the trace selection mode.
    /// </summary>
    [JsonPropertyName(@"type")]
    public string Type { get; init; } = @"agent_filter";

    /// <summary>
    /// Gets the deployed agent name recorded in telemetry.
    /// </summary>
    [JsonPropertyName(@"agent_name")]
    public required string AgentName { get; init; }

    /// <summary>
    /// Gets the beginning of the window in Unix seconds.
    /// </summary>
    [JsonPropertyName(@"start_time")]
    public required long StartTime { get; init; }

    /// <summary>
    /// Gets the end of the window in Unix seconds.
    /// </summary>
    [JsonPropertyName(@"end_time")]
    public required long EndTime { get; init; }

    /// <summary>
    /// Gets the maximum number of traces requested for this window.
    /// </summary>
    [JsonPropertyName(@"max_traces")]
    public required int MaxTraces { get; init; }
}
