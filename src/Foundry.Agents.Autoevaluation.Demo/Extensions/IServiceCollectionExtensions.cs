using Foundry.Agents.Autoevaluation.Demo.Options;
using Foundry.Agents.Autoevaluation.Demo.Services;

using Microsoft.Extensions.Options;

namespace Microsoft.Extensions.DependencyInjection;

internal static class IServiceCollectionExtensions
{
    /// <summary>
    /// Adds the Foundry continuous evaluation background service to the <see cref="IServiceCollection"/>.
    /// Options are bound from the <c>FoundryContinuousEvaluationOptions</c> configuration section.
    /// </summary>
    /// <param name="services">The <see cref="IServiceCollection"/> to add the service to.</param>
    /// <param name="configuration">The application configuration.</param>
    /// <param name="agentId">The ID of the agent whose traces will be evaluated.</param>
    /// <param name="agentName">The name of the agent whose traces will be evaluated.</param>
    /// <param name="foundryProjectEndpoint">The endpoint of the Foundry project.</param>
    /// <returns>The <see cref="IServiceCollection"/> so that additional calls can be chained.</returns>
    public static IServiceCollection AddFoundryContinuousEvaluation(this IServiceCollection services, IConfiguration configuration, string agentId, string agentName, Uri foundryProjectEndpoint)
    {
        services.AddOptionsWithValidateOnStart<FoundryContinuousEvaluationOptions>()
                .Bind(configuration.GetSection(nameof(FoundryContinuousEvaluationOptions)))
                .PostConfigure(options =>
                {
                    if (string.IsNullOrWhiteSpace(options.ModelDeploymentName))
                    {
                        options.ModelDeploymentName = configuration[@"AZURE_AI_MODEL_DEPLOYMENT_NAME"] ?? string.Empty;
                    }
                })
                .ValidateDataAnnotations()
                .Validate(options => options.Evaluators.All(FoundryEvaluationConfiguration.IsSupportedEvaluator), @"Select evaluators supported by this trace-only demo.")
                .Validate(options => options.Evaluators.Distinct(StringComparer.Ordinal).Count() == options.Evaluators.Count, @"Evaluator names must be unique.")
                .Validate(options => double.IsFinite(options.TraceSamplingPercentage), @"TraceSamplingPercentage must be finite.");

        services.AddHostedService(serviceProvider =>
        {
            var optionsMonitor = serviceProvider.GetRequiredService<IOptionsMonitor<FoundryContinuousEvaluationOptions>>();
            var logger = serviceProvider.GetRequiredService<ILogger<FoundryContinuousEvaluationService>>();

            return new FoundryContinuousEvaluationService(agentId, agentName, foundryProjectEndpoint, optionsMonitor, logger);
        });

        return services;
    }
}
