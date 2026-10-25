#pragma warning disable AAIP001 // The evaluator catalog is experimental in the installed SDK.

using System.ClientModel.Primitives;
using System.Security.Cryptography;

using Azure.AI.Projects;
using Azure.AI.Projects.Evaluation;

using Foundry.Agents.Autoevaluation.Demo.Models;
using Foundry.Agents.Autoevaluation.Demo.Options;

namespace Foundry.Agents.Autoevaluation.Demo.Services;

internal static class FoundryEvaluationConfiguration
{
    internal const string LinksEvaluatorName = @"official_microsoft_links";
    internal const string CommunicationEvaluatorName = @"corporate_communication";

    internal static bool IsSupportedEvaluator(string? name) => name is
        @"builtin.relevance" or
        @"builtin.coherence" or
        @"builtin.fluency" or
        @"builtin.violence" or
        LinksEvaluatorName or
        CommunicationEvaluatorName;

    internal static EvaluatorVersion? CreateCustomEvaluator(string name) => name switch
    {
        LinksEvaluatorName => CreateLinksEvaluator(),
        CommunicationEvaluatorName => CreateCommunicationEvaluator(),
        _ => null,
    };

    internal static string GetCatalogName(string name, EvaluatorVersion evaluator)
    {
        var definition = ModelReaderWriter.Write(evaluator.Definition);
        var hash = Convert.ToHexStringLower(SHA256.HashData(definition.ToMemory().Span));
        return $@"{name}_{hash[..12]}";
    }

    internal static FoundryEvaluationCreateRequest CreateRequest(FoundryContinuousEvaluationOptions options)
    {
        var criteria = options.Evaluators.Select(name =>
        {
            var custom = CreateCustomEvaluator(name);
            var parameters = new Dictionary<string, object>();
            var mapping = new Dictionary<string, string> { [@"response"] = @"{{item.response}}" };

            if (name is not (@"builtin.fluency" or LinksEvaluatorName))
            {
                mapping[@"query"] = @"{{item.query}}";
            }

            if (name == @"builtin.violence")
            {
                parameters[@"threshold"] = options.SafetySeverityThreshold;
            }
            else
            {
                parameters[@"deployment_name"] = options.ModelDeploymentName;
                parameters[name == LinksEvaluatorName ? @"pass_threshold" : @"threshold"] = name switch
                {
                    LinksEvaluatorName => 1,
                    CommunicationEvaluatorName => options.CommunicationPassThreshold,
                    _ => options.QualityPassThreshold,
                };
            }

            return new FoundryEvaluationTestingCriterion
            {
                Name = name.StartsWith(@"builtin.", StringComparison.Ordinal) ? name[@"builtin.".Length..] : name,
                EvaluatorName = custom is null ? name : GetCatalogName(name, custom),
                DataMapping = mapping,
                InitializationParameters = parameters,
            };
        }).ToList();

        var configuration = BinaryData.FromObjectAsJson(new { scenario = @"traces", testing_criteria = criteria });
        var hash = Convert.ToHexStringLower(SHA256.HashData(configuration.ToMemory().Span));

        return new FoundryEvaluationCreateRequest
        {
            Name = options.EvaluationName,
            DataSourceConfig = new FoundryEvaluationDataSourceConfig(),
            TestingCriteria = criteria,
            Metadata = new Dictionary<string, string> { [@"configuration_hash"] = hash },
        };
    }

    internal static FoundryEvaluationRunRequest CreateRunRequest(FoundryContinuousEvaluationOptions options, string agentName, string evaluationId)
    {
        if (options.TraceSamplingPercentage <= 0)
        {
            throw new InvalidOperationException(@"No evaluation run should be submitted when sampling is disabled.");
        }

        var now = DateTimeOffset.UtcNow;

        return new FoundryEvaluationRunRequest
        {
            EvalId = evaluationId,
            Name = $@"{evaluationId}-{now:yyyyMMdd-HHmmss}",
            DataSource = new FoundryEvaluationRunDataSource
            {
                TraceSource = new FoundryEvaluationTraceSource
                {
                    AgentName = agentName,
                    StartTime = now.AddHours(-options.LookbackHours).ToUnixTimeSeconds(),
                    EndTime = now.ToUnixTimeSeconds(),
                    MaxTraces = Math.Max(1, (int)Math.Round(options.MaxTracesPerRun * options.TraceSamplingPercentage / 100d)),
                },
            },
        };
    }

    private static EvaluatorVersion CreateLinksEvaluator()
    {
        var initParameters = BinaryData.FromObjectAsJson(new
        {
            type = @"object",
            properties = new Dictionary<string, object>
            {
                [@"deployment_name"] = new { type = @"string" },
                [@"pass_threshold"] = new { type = @"number" },
            },
            required = new[] { @"deployment_name", @"pass_threshold" },
        });

        var responseSchema = new
        {
            type = @"object",
            properties = new
            {
                query = new { type = @"string" },
                response = new { type = @"string" },
            },
            required = new[] { @"response" },
        };

        var metric = new EvaluatorMetric
        {
            Type = EvaluatorMetricType.Continuous,
            DesirableDirection = EvaluatorMetricDirection.Increase,
            MinValue = 0,
            MaxValue = 1,
        };

        var definition = new CodeBasedEvaluatorDefinition(
            codeText: ReadResource(@"official_microsoft_links.py"),
            initParameters: initParameters,
            dataSchema: BinaryData.FromObjectAsJson(responseSchema),
            metrics: new Dictionary<string, EvaluatorMetric> { [@"result"] = metric });

        return new EvaluatorVersion(
            categories: [EvaluatorCategory.Quality],
            definition: definition,
            evaluatorType: EvaluatorType.Custom)
        {
            DisplayName = @"Official Microsoft links",
            Description = @"Checks explicit web URLs against an exact HTTPS Microsoft-domain allowlist; does not verify facts or follow links.",
        };
    }

    private static EvaluatorVersion CreateCommunicationEvaluator()
    {
        var initParameters = BinaryData.FromObjectAsJson(new
        {
            type = @"object",
            properties = new Dictionary<string, object>
            {
                [@"deployment_name"] = new { type = @"string" },
                [@"threshold"] = new { type = @"number" },
            },
            required = new[] { @"deployment_name", @"threshold" },
        });

        var responseSchema = new
        {
            type = @"object",
            properties = new
            {
                query = new { type = @"string" },
                response = new { type = @"string" },
            },
            required = new[] { @"query", @"response" },
        };

        var metric = new EvaluatorMetric
        {
            Type = EvaluatorMetricType.Ordinal,
            DesirableDirection = EvaluatorMetricDirection.Increase,
            MinValue = 1,
            MaxValue = 5,
        };

        var definition = new PromptBasedEvaluatorDefinition(
            promptText: ReadResource(@"corporate_communication.txt"),
            initParameters: initParameters,
            dataSchema: BinaryData.FromObjectAsJson(responseSchema),
            metrics: new Dictionary<string, EvaluatorMetric> { [@"custom_prompt"] = metric });

        return new EvaluatorVersion(
            categories: [EvaluatorCategory.Quality],
            definition: definition,
            evaluatorType: EvaluatorType.Custom)
        {
            DisplayName = @"Corporate communication",
            Description = @"Scores language choice, professional tone, and practical guidance for enterprise conversations.",
        };
    }

    private static string ReadResource(string fileName)
    {
        var assembly = typeof(FoundryEvaluationConfiguration).Assembly;
        var resourceName = $@"{assembly.GetName().Name}.EmbeddedResources.{fileName}";
        using var stream = assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($@"Evaluator resource '{resourceName}' is missing.");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}

#pragma warning restore AAIP001 // The evaluator catalog is experimental in the installed SDK.
