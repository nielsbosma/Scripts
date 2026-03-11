# IvyAgentDebug

Analyze review data from an Ivy Agent session and generate actionable improvement plans.

## Context

By the time you run, these review scripts have already completed and produced files in `{WorkDir}/.ivy/`:

- **ReviewBuild** → `review-build.md`
- **ReviewLangfuse** → `langfuse-timeline.md`, `langfuse-build-errors.md`, `langfuse-docs.md`, `langfuse-hallucinations.md`, `langfuse-questions.md`, `langfuse-reference-connections.md`, `langfuse-workflows.md`
- **ReviewSpec** → `review-spec.md`
- **ReviewTests** → `review-tests.md`, `review-ux.md`

Read about the important paths and files in `../.shared/Paths.md`

Read `/Memory/Langfuse.md` for Langfuse JSON structure reference if you need to inspect raw data.

Plans are stored in `D:\Repos\_Ivy\.plans\`. Each plan gets a sequential numeric ID from the counter file `.counter` in that directory.

## Execution Steps

### 1. Read All Reviews

Read every review file in `{WorkDir}/.ivy/`:

- `.ivy/spec.md` — the original spec
- `.ivy/review-build.md` — build review
- `.ivy/review-spec.md` — spec compliance review
- `.ivy/review-tests.md` — test results, project fixes applied, external issues
- `.ivy/review-ux.md` — UX/screenshot review
- `.ivy/langfuse-timeline.md` — session timeline
- `.ivy/langfuse-build-errors.md` — all build errors
- `.ivy/langfuse-docs.md` — docs read by the agent (and 404s)
- `.ivy/langfuse-hallucinations.md` — hallucination analysis
- `.ivy/langfuse-questions.md` — IvyQuestion Q&A log
- `.ivy/langfuse-reference-connections.md` — reference connections used
- `.ivy/langfuse-workflows.md` — workflow execution details

If a file is missing, note it and continue with what's available.

Also check for `.ivy/annotated.md` — this contains the client TUI output annotated by the user with `>>` prefixed lines. These annotations are the user's own observations about what went wrong and should be investigated with **highest priority**. Look for every `>>` line and address each one.

Also check for `.ivy/feedback.md` — this contains free-form feedback from the user. Like annotations, this feedback should be treated with **highest priority** and should influence your analysis and plan generation in Step 3.

Check the logs:  

IVY_AGENT_DEBUG_FOLDER\<session-id>\
  <session-id>-client-verbose.log
  <session-id>-client-output.log
  <session-id>-server-verbose.log
  <task-trace-id>-client-verbose.log
  <task-trace-id>-server-verbose.log

Anything that stands out that we should look into?

### 2. Search GitHub Issues

Before creating plans, search GitHub issues to check if a finding is already tracked or has a planned fix. This avoids creating workaround plans for things that are already being built.

```bash
# Search across all main Ivy repos
gh search issues "<keyword>" --repo Ivy-Interactive/Ivy-Framework --repo Ivy-Interactive/Ivy-Agent --repo Ivy-Interactive/Ivy-Mcp --repo Ivy-Interactive/Ivy --json title,url,number,state
```

Key repos to search: `Ivy-Interactive/Ivy-Framework`, `Ivy-Interactive/Ivy-Agent`, `Ivy-Interactive/Ivy-Mcp`, `Ivy-Interactive/Ivy`, `Ivy-Interactive/Ivy-Inspectors`

If a GitHub issue already covers a finding:
- Reference the issue in the plan (e.g. `See: Ivy-Framework#2398`)
- Don't create workaround plans (e.g. FAQ entries) for features that are already being built — instead note the issue is in progress
- If the finding adds new context to an existing issue, consider commenting on the issue or creating a plan that references it

### 3. Investigate & Generate Plans

This is a very large task. Feel free to split this up in multiple sub tasks.

Now to the main goal: by analysing all the collected data your task is to come up with plans for how to improve the outcome of the Ivy Agent. 

This can be achieve in many ways:

- Change Ivy-Framework (fix bugs, update APIs to match hallucinations)
- Did the agent struggle in any way to implement a specific design goal - are we missing any API for this?
- Improve Ivy-Agent (fix bugs, improve token usage, performance, tool instructions, persona usage, ...)
- Make sure to review <session-id>-client-output.log for any sign of the session not being a "one-shot"
- Fix bugs in agent clients (Ivy Studio, Tui, NonInteractive)
- Strengthen documentation
- Improve agent workflows and reference connections to provide better context to agent when used
- Add refactorings after code generation
- Add analysers to Ivy.Analyser to make common runtime errors into compile time errors. We really want to avoid runtime errors!

For each issue found across the reviews, investigate and create a plan. Search existing plans first to avoid duplicates.

NOTES:

#### Build Errors
- If `langfuse-build-errors.md` shows errors, cross-reference with `langfuse-hallucinations.md`
- Distinguish: hallucination vs missing package vs framework bug vs user code bug
- Could the build error be avoided by improving any part of the agent?

#### Workflow Issues
- If `langfuse-workflows.md` shows failures, read the workflow source files
- Check state transitions and prompt templates for issues

#### Test Failures & UX Issues
- If `review-tests.md` shows external issues, document them as plans
- If `review-ux.md` has recommendations, assess if they point to framework widget gaps - anything we can improve in the agent?

#### Hallucinations
- If `langfuse-hallucinations.md` reports hallucinated APIs, check if a refactoring rule could prevent it
- Check `D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared\Docs` for missing or unclear documentation
- Add to `D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared\Docs\05_Other\Hallucinations.md` (if not already there)
- Check if samples cover the misused pattern
- When updating Hallucinations.md we should also check if some sections can be removed. We might have updated the APIs in Ivy-Framework. 

#### Failed Questions
- If `langfuse-questions.md` shows failed IvyQuestion calls, check if the answer should exist in:
  - `D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared\Docs\05_Other\Faq.md`
  - Or a dedicated doc page
- Check if the question is already in the FAQ — if so, assess if the answer needs improvement
- NOTE! Just because we have documented something in Faq.md doesn't mean that IvyMcp has been updated wiht that info yet.
- When updating FAQ.md we should also check if some sections can be removed. We might have updated the APIs in Ivy-Framework. 

#### Doc 404s
- If `langfuse-docs.md` shows failed doc reads, check what path was requested and whether:
  - The doc exists at a different path
  - The doc should be created
  - The agent's doc path resolution has a bug

### 4. Create Plan Files

For each actionable finding, create a plan file in `D:\Repos\_Ivy\.plans\`.

- Read the counter from `.counter` (default 200 if missing), allocate IDs, increment
- Format: `<ID>-<RepositoryName>-Feature-<Title>.md`
- Repository names: `IvyAgent`, `IvyConsole`, `IvyFramework`, `General`
- Before creating a plan, search existing plans to avoid duplicates — update existing plans if they partially cover the finding
- Read `{WorkDir}/.ivy/plans.md` if it exists — this lists plans created in previous runs of this script. Skip creating plans already listed there
- After creating new plans, append their paths to `{WorkDir}/.ivy/plans.md` (create the file if it doesn't exist) using this format:
  ```markdown
  # Created Plans

  - D:\Repos\_Ivy\.plans\268-Scripts-Feature-Example.md
  ```

Plan format:

```markdown
---
source: {WorkDir}/.ivy/
session: {SessionId}
---
# [Title]

## Problem

[What went wrong, with evidence from review files]

## Solution

[Concrete steps — include file paths, code patterns, API names]

## Clean up

1. Commit
```

### Rules

- **Everything must be expressed as plans** — hallucination fixes, FAQ edits, doc improvements, workflow fixes
- ONE issue per plan file
- Plans must include all paths and information for an LLM coding agent to execute end-to-end
- Keep plans short and concise
- Do NOT modify any source code directly — only read files and create plan files
- Missing review files are not failures — analyze what's available

## Finally 

Give that you are an orchestrator - feel free to make improvements to:

D:\Repos\_Personal\Scripts\AF2\IvyAgentReviewBuild
D:\Repos\_Personal\Scripts\AF2\IvyAgentReviewLangfuse
D:\Repos\_Personal\Scripts\AF2\IvyAgentReviewSpec
D:\Repos\_Personal\Scripts\AF2\IvyAgentReviewTests

According to the the D:\Repos\_Personal\Scripts\AF2\.shared\Firmware.md instructors if you feel that the output from these skills can be improved for you to optimize your future performance. 