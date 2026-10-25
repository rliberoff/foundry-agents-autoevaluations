using System.Text.Json.Serialization;

namespace Foundry.Agents.Autoevaluation.Demo.Models;

/// <summary>
/// The data source configuration for a Foundry evaluation group.
/// </summary>
internal sealed class FoundryEvaluationDataSourceConfig
{
    /// <summary>
    /// Gets the type of the data source configuration. Always <c>azure_ai_source</c>.
    /// </summary>
    [JsonPropertyName(@"type")]
    public string Type { get; init; } = @"azure_ai_source";

    /// <summary>
    /// Gets the scenario of the data source configuration. Always <c>traces</c>.
    /// </summary>
    [JsonPropertyName(@"scenario")]
    public string Scenario { get; init; } = @"traces";
}
