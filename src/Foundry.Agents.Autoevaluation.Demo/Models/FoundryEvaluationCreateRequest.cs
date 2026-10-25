using System.Text.Json.Serialization;

namespace Foundry.Agents.Autoevaluation.Demo.Models;

/// <summary>
/// A request to create a Foundry evaluation group scoped to Application Insights agent traces.
/// </summary>
internal sealed class FoundryEvaluationCreateRequest
{
    /// <summary>
    /// Gets the name of the evaluation group.
    /// </summary>
    [JsonPropertyName(@"name")]
    public required string Name { get; init; }

    /// <summary>
    /// Gets the data source configuration for the evaluation group.
    /// </summary>
    [JsonPropertyName(@"data_source_config")]
    public required FoundryEvaluationDataSourceConfig DataSourceConfig { get; init; }

    /// <summary>
    /// Gets the list of testing criteria (evaluators) to run against sampled traces.
    /// </summary>
    [JsonPropertyName(@"testing_criteria")]
    public required IReadOnlyList<FoundryEvaluationTestingCriterion> TestingCriteria { get; init; }

    /// <summary>
    /// Gets the configuration fingerprint used to reuse only matching evaluation groups.
    /// </summary>
    [JsonPropertyName(@"metadata")]
    public required IReadOnlyDictionary<string, string> Metadata { get; init; }
}