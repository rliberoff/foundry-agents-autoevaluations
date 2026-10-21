# Microsoft Foundry Agents Auto-Evaluations

Evaluating agents with synthetic datasets has limits: they rarely match real user behavior in production. This demo shows an end-to-end workflow to transform production traces from a Hosted Agent instrumented with OpenTelemetry into structured evaluation datasets, then run continuous, evidence‑based evaluations to obtain actionable metrics on accuracy, helpfulness, safety, and alignment.

## Architecture and Components

### Instrumentation

- Hosted Agent instrumented with OpenTelemetry to capture spans and events.
- Application Insights as the telemetry sink for production traces.

### Data Pipeline

- Trace extraction from Application Insights.
- Trace transformation into evaluation records and dataset schema.
- Dataset storage compatible with Foundry evaluation tooling.

### Evaluation Layer

- Custom evaluators implemented in C# or Python.
- LLM-as-a-judge patterns for subjective judgments.
- Continuous Evaluations in Foundry to run periodic or streaming assessments.

## End to End Workflow

1. **Capture**: Collect production traces via OpenTelemetry into Application Insights.
2. **Extract**: Pull relevant traces and interaction metadata from Application Insights.
3. **Transform**: Convert traces into evaluation records (inputs, agent responses, context, ground truth if available).
4. **Assemble**: Build evaluation datasets and upload them to Foundry.
5. **Evaluate**: Configure custom evaluators or LLM-judge pipelines and run Continuous Evaluations.
6. **Iterate**: Use metrics and failure cases to refine the agent and repeat the cycle.

## Deploy the hosted agent

Run commands from the repository root. Install Azure Developer CLI with the `azure.ai.agents` extension (at least `1.0.0-beta.12`), Terraform matching the pinned provider requirements, and authenticate with Azure. Local Docker is not required: Azure Container Registry Tasks builds the image remotely.

Select an azd environment with `AZURE_SUBSCRIPTION_ID`, `AZURE_LOCATION`, and `TF_VAR_suffix` configured. The suffix must contain exactly five lowercase letters or digits. Choose a region that supports both hosted agents and the model configured in Terraform, with sufficient quota.

Provision the infrastructure, build and publish the image, and deploy the agent:

```powershell
azd up
```

The native azd workflow provisions Terraform's `backend` and `resources` layers before publishing and deploying `agent-autoevaluations` to the Foundry project. Package preparation can overlap with provisioning; the remote image build and publication run once the infrastructure is available. Keep the native workflow instead of overriding `workflows.up`, so service-target extensions remain available throughout execution. The Docker build uses the repository root as its context so the shared .NET build and package configuration is available. Images use azd-generated version tags.

Terraform exports the ACR and Foundry settings into the azd environment, connects the project to ACR and Application Insights, and grants the provisioning identity Foundry User access on the project. The project managed identity already receives `AcrPull` through the ACR module. The provisioning identity also needs resource creation and role-assignment permissions; the deployment identity needs permission to run ACR Tasks and publish images. If provisioning and deployment use different identities, grant the deployment identity Foundry project access separately. See the [hosted agent permissions reference](https://learn.microsoft.com/azure/foundry/agents/concepts/hosted-agent-permissions).

The demo uses the first deployment in Terraform's `foundry_models` list. Foundry injects `FOUNDRY_PROJECT_ENDPOINT` and `APPLICATIONINSIGHTS_CONNECTION_STRING` into the hosted container; do not set them in the agent service definition. The server listens on port `8088`.

After provisioning, publish code changes without rerunning Terraform:

```powershell
azd deploy agent-autoevaluations
```

Each deployment creates a new agent version. To check the deployed agent and send a smoke-test request, which incurs model usage charges:

```powershell
azd ai agent show
azd ai agent invoke "Introduce yourself in one sentence."
```

## SDKs and Examples

- **Portal**: Guided steps to create datasets and configure Continuous Evaluations from the Foundry portal.
- **C# SDK**: Examples for extracting traces, transforming records, and registering evaluators.
- **Python SDK**: Scripts for trace processing, dataset generation, and evaluator integration.

## Best Practices and Notes

- **Prioritize privacy and compliance** when using production traces; redact or anonymize PII before dataset creation.
- **Start with a small sample** of traces to validate transformation logic before scaling.
- **Combine automated evaluators with periodic human review** for edge cases.
- **Track metrics over time** to measure the impact of changes and avoid regressions.
