using System.Text.Json.Serialization;

namespace Foundry.Agents.Autoevaluation.Demo.Models;

/// <summary>
/// A request to trigger an evaluation run against sampled Application Insights agent traces.
/// </summary>
internal sealed class FoundryEvaluationRunRequest
{
    /// <summary>
    /// Gets the ID of the evaluation group this run belongs to.
    /// </summary>
    [JsonPropertyName(@"eval_id")]
    public required string EvalId { get; init; }

    /// <summary>
    /// Gets the name of the run.
    /// </summary>
    [JsonPropertyName(@"name")]
    public required string Name { get; init; }

    /// <summary>
    /// Gets the data source describing which traces to sample for this run.
    /// </summary>
    [JsonPropertyName(@"data_source")]
    public required FoundryEvaluationRunDataSource DataSource { get; init; }
}
