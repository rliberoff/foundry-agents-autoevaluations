# Agent instructions

Guidance for any AI coding assistant working in this repository.

## Project overview

This document describes how to close the observability loop for Generative AI agents running on Microsoft Foundry by converting real production traces from Application Insights into evaluation datasets. It explains instrumentation, dataset creation, custom evaluators, and Continuous Evaluations to measure and improve agent quality using real user behavior.

Evaluating agents with synthetic datasets has limits: they rarely match real user behavior in production. This guide shows an end-to-end workflow to transform production traces from a Hosted Agent instrumented with OpenTelemetry into structured evaluation datasets, then run continuous, evidence‑based evaluations to obtain actionable metrics on accuracy, helpfulness, safety, and alignment.

## Order of precedence

All applicable sources below apply together. Precedence only matters when two of them conflict.

| Priority | Source | What it governs |
| :--- | :--- | :--- |
| 1 | A direct, explicit user directive | Overrides everything below, except the [Safety and boundaries](#safety-and-boundaries) section |
| 2 | Scoped rules in [`.github/instructions/`](.github/instructions/) | Rules for the files matched by their `applyTo` glob; they refine this file for those files |
| 3 | Skills in `.agents/skills/<skill_name>/SKILL.md` | Domain conventions, applied when the skill description matches the task |
| 4 | This file | Defaults for interaction style, language, code generation and modification |

A more specific source refines a more general one; that is not a conflict. A conflict exists only when two sources cannot both be satisfied. In that case, or when a source referenced here cannot be found or loaded, stop the affected work and ask the user to resolve it rather than choosing one yourself.

### Loading scoped rules and skills

Not every assistant discovers these files automatically, so do it explicitly:

- Before creating or editing a file, read every file in `.github/instructions/` whose `applyTo` glob matches that file's path.
- Before starting a task, check the descriptions in `.agents/skills/*/SKILL.md` and read any skill that matches the task.

## Safety and boundaries

These rules apply even when a user directive says otherwise. If a directive requires breaking one, explain why and ask for confirmation instead of acting.

- Never commit, print, or log secrets, keys, connection strings, or credentials. Use Azure Key Vault or user secrets instead.
- Never run `terraform apply`, `terraform destroy`, or any command that changes cloud resources or non-local environments.
- Never force-push, rewrite published history, or delete branches.
- Ask for confirmation before any destructive or irreversible action, such as deleting files or dropping data.

## Clarification before implementation

Follow [`.github/instructions/wow-follow-up-question.instructions.md`](.github/instructions/wow-follow-up-question.instructions.md). Ask before implementing when:

- The scope or acceptance criteria are ambiguous or missing.
- There are several reasonable designs with different trade-offs.
- The change affects a public API, a data schema, or infrastructure.
- The request contradicts existing code or another rule.

## Factual verification

For anything version-dependent or time-sensitive, such as library APIs, SDK versions, or current recommendations, verify with tools instead of relying on memory. Prefer the documentation tools available to you, such as Microsoft Learn MCP server for Azure and .NET, and cite the source in your answer.

## Language policy

- **Code and development materials** (namespaces, classes, methods, variables, comments, commit messages) must be in English.
- **Agent configuration** (files in `.github/instructions/`, `.github/prompts/`, `.github/agents/`, and `.agents/skills/`) must be in English.
- **Contributor documentation** (README.md, CONTRIBUTING.md, etc.) must be in English.
- **End-user content** (UI labels, user-facing messages, etc.) may be in Spanish as the project requires.
- **Conversation**: reply in the language the user writes in.

## Code generation

- **Follow `.editorconfig`**: when the solution has one, all generated code must follow its style and conventions.
- **Simplicity**: provide the most straightforward solution that solves the problem. Avoid premature optimization, over-engineering, and "clever" or obscure patterns.
- **Standard first**: prefer the standard library and common, proven patterns. Add a third-party dependency only when it is the industry standard for the task or truly necessary.
- **Trusted dependencies**: packages from Microsoft, the .NET Foundation, and the official Terraform Providers registry. Use stable versions only, and reuse the versions already pinned in the repository.
- **Scope**: implement what was requested, without unrequested features. Still handle the input validation, error handling, and security checks the code needs to be correct.

## Code modification

- **Follow existing conventions**: the codebase is the source of truth for structure, style, and patterns. If existing code deviates from best practice, follow it anyway and mention the deviation; do not fix it unless asked.
- **Minimal changes**: change the least code needed, and integrate new logic into existing structures rather than replacing whole functions or blocks.
- **Explicit targets only**: do not refactor, clean up, or restyle code the request did not target.
- **Edit directly**: when asked to change code and you have access to the repository, apply the changes to the files instead of producing snippets to copy.

## Interaction and tool usage

- **Be concise**: answer precisely, without filler.
- **Explain the why briefly**: give one or two sentences on why the chosen approach is the standard one, with a link to authoritative documentation when one exists.
- **Declare side effects**: before any action that changes something (editing files, running commands that write or install, committing), state in one line what you are about to do and why. Reading and searching need no announcement.
- **Stay on task**: every tool call must serve the current request.

## Markdown documentation

Follow the [`coding-style-markdown`](.agents/skills/coding-style-markdown/SKILL.md) skill whenever you create or modify a Markdown file, including this one.

## Commits and pull requests

Follow the [`wow-conventional-commits`](.agents/skills/wow-conventional-commits/SKILL.md) skill for commit messages and pull request titles. Extend this to pull request descriptions and branch names if the skill covers them.

## Technology stack

- **.NET SDK**: 10.0.402
- **C# Language Version**: 13.0
