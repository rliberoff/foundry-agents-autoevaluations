using System.Text.Json.Serialization;

namespace Foundry.Agents.Autoevaluation.Demo.Models;

/// <summary>
/// The data source describing which Application Insights agent traces to sample for an evaluation run.
/// </summary>
internal sealed class FoundryEvaluationRunDataSource
{
    /// <summary>
    /// Gets the type of the data source. Always <c>azure_ai_trace_data_source_preview</c>.
    /// </summary>
    [JsonPropertyName(@"type")]
    public string Type { get; init; } = @"azure_ai_trace_data_source_preview";

    /// <summary>
    /// Gets the deployed-agent filter and explicit time window.
    /// </summary>
    [JsonPropertyName(@"trace_source")]
    public required FoundryEvaluationTraceSource TraceSource { get; init; }
}
