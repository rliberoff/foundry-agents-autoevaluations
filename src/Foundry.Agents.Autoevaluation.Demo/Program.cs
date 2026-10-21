using System.Diagnostics;

using Azure.AI.Projects;
using Azure.Identity;

using DotNetEnv;

using Microsoft.Agents.AI;
using Microsoft.Agents.AI.Foundry.Hosting;

// AgentHost.CreateBuilder() auto-configures:
//   - Kestrel on port 8088 (or the PORT environment variable)
//   - GET /readiness health probe
//   - OpenTelemetry traces and metrics
//   - x-platform-server response header
var builder = AgentHost.CreateBuilder(args);

/* Load Configuration */

// Load environment variables from a .env file if present (for local development).
// Load in precedence order: base -> environment -> user
Env.TraversePath().LoadMulti(
[
    @".env",
    $@".env.{builder.WebApplicationBuilder.Environment.EnvironmentName}",
    $@".env.{Environment.UserName}",
]);

if (Debugger.IsAttached)
{
    Env.TraversePath().Load($@".env.debug");
}

builder.WebApplicationBuilder.Configuration.AddEnvironmentVariables();

if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable(@"APPLICATIONINSIGHTS_CONNECTION_STRING")))
{
    await Console.Error.WriteLineAsync(@"[WARNING] `APPLICATIONINSIGHTS_CONNECTION_STRING` environmental variable not set! Traces will not be sent to Application Insights. Set it to enable local telemetry. This environmental variable is auto-injected in hosted Microsoft Foundry containers, do not declare it on your own!");
}

var endpointFoundryProject = builder.Configuration[@"FOUNDRY_PROJECT_ENDPOINT"] ?? throw new InvalidOperationException(@"`FOUNDRY_PROJECT_ENDPOINT` environment variable is not set!");
var aiModelDeploymentName = builder.Configuration[@"AZURE_AI_MODEL_DEPLOYMENT_NAME"] ?? throw new InvalidOperationException(@"`AZURE_AI_MODEL_DEPLOYMENT_NAME` environment variable is not set!");

// Create an AI Agent backed by a Foundry model.
// The agent framework manages the LLM call, conversation sessions, and response lifecycle.
AIAgent agent = new AIProjectClient(new Uri(endpointFoundryProject), new DefaultAzureCredential())
    .AsAIAgent(
        model: aiModelDeploymentName,
        instructions: @"You are a helpful AI assistant. Be concise and informative. You name is Dereck, and your version is 1.",
        name: @"agent-autoevaluations",
        description: @"A minimal Hello World agent using the Agent Framework");

builder.Services.AddFoundryResponses(agent);
builder.RegisterProtocol(@"responses", endpoints => endpoints.MapFoundryResponses());

var app = builder.Build();

await app.RunAsync();
