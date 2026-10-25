using System.Text.Json.Serialization;

namespace Foundry.Agents.Autoevaluation.Demo.Models;

/// <summary>
/// A single testing criterion (evaluator) within a Foundry evaluation group.
/// </summary>
internal sealed class FoundryEvaluationTestingCriterion
{
    /// <summary>
    /// Gets the type of the testing criterion. Always <c>azure_ai_evaluator</c>.
    /// </summary>
    [JsonPropertyName(@"type")]
    public string Type { get; init; } = @"azure_ai_evaluator";

    /// <summary>
    /// Gets the short name of the evaluator (e.g. <c>fluency</c>).
    /// </summary>
    [JsonPropertyName(@"name")]
    public required string Name { get; init; }

    /// <summary>
    /// Gets the fully qualified name of the built-in evaluator (e.g. <c>builtin.fluency</c>).
    /// </summary>
    [JsonPropertyName(@"evaluator_name")]
    public required string EvaluatorName { get; init; }

    /// <summary>
    /// Gets the mapping from evaluator inputs to trace fields.
    /// </summary>
    [JsonPropertyName(@"data_mapping")]
    public required IReadOnlyDictionary<string, string> DataMapping { get; init; }

    /// <summary>
    /// Gets the initialization parameters for the evaluator.
    /// </summary>
    [JsonPropertyName(@"initialization_parameters")]
    public required IReadOnlyDictionary<string, object> InitializationParameters { get; init; }
}
