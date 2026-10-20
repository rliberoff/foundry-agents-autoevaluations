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

## SDKs and Examples

- **Portal**: Guided steps to create datasets and configure Continuous Evaluations from the Foundry portal.
- **C# SDK**: Examples for extracting traces, transforming records, and registering evaluators.
- **Python SDK**: Scripts for trace processing, dataset generation, and evaluator integration.

## Best Practices and Notes

- **Prioritize privacy and compliance** when using production traces; redact or anonymize PII before dataset creation.
- **Start with a small sample** of traces to validate transformation logic before scaling.
- **Combine automated evaluators with periodic human review** for edge cases.
- **Track metrics over time** to measure the impact of changes and avoid regressions.
