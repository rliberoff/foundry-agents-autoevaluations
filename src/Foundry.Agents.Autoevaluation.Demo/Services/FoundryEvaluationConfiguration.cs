using Foundry.Agents.Autoevaluation.Demo.Models;
using Foundry.Agents.Autoevaluation.Demo.Options;

namespace Foundry.Agents.Autoevaluation.Demo.Services;

internal static class FoundryEvaluationConfiguration
{
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
            Name = $@"{now:yyyyMMdd-HHmmss}",
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
}
