# IvyAgentDebug

Analyze review data from an Ivy Agent session and generate actionable improvement plans.

## Context

By the time you run, these review scripts have already completed and produced files in `{WorkDir}/.ivy/`:

- **ReviewBuild** → `review-build.md`
- **ReviewLangfuse** → `langfuse-timeline.md`, `langfuse-build-errors.md`, `langfuse-docs.md`, `langfuse-hallucinations.md`, `langfuse-questions.md`, `langfuse-reference-connections.md`, `langfuse-workflows.md`, `langfuse-system-reminders.md`
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
- `.ivy/langfuse-system-reminders.md` — system reminder events and effectiveness

If a file is missing, note it and continue with what's available.

Also check for `.ivy/annotated.md` — this contains the client TUI output annotated by the user with `>>` prefixed lines. These annotations are the user's own observations about what went wrong and should be investigated with **highest priority**. Look for every `>>` line and address each one.

Also check for `.ivy/feedback.md` — this contains free-form feedback from the user. Like annotations, this feedback should be treated with **highest priority** and should influence your analysis and plan generation in Step 3.

Check the logs:  

{WorkDir}/.ivy/sessions/<session-id>/
  <session-id>-client-verbose.log
  <session-id>-client-output.log
  <session-id>-server-verbose.log
  <task-trace-id>-client-verbose.log
  <task-trace-id>-server-verbose.log
  langfuse/

Anything that stands out that we should look into?

### 1b. Cross-Reference Pending Review Files

Check `D:\Repos\_Ivy\.plans\review\` for any review/verification files. For each file:

1. **Parse the review checklist** — extract the plan ID, what was changed, and each verification item
2. **Match against current session data**:
   - If the review mentions a **widget or API** (e.g., DataTable, Empty state), check:
     - `langfuse-hallucinations.md` for hallucinated usage of that API
     - `langfuse-build-errors.md` for build errors related to that API
     - `review-ux.md` / screenshots for visual evidence
     - `langfuse-timeline.md` for tool calls involving that feature
   - If the review mentions **token/cost metrics**, check:
     - `summary.yaml` for token counts
     - `langfuse-timeline.md` for per-generation data
     - Langfuse raw data for cache metrics (`cacheRead`, `cacheCreationInputTokens`)
   - If the review mentions **analyser behavior**, check:
     - `langfuse-system-reminders.md` for analyser firing patterns
     - `langfuse-build-errors.md` for build retry counts
   - If the review mentions **specific sessions**, check if the current session ID matches
3. **Annotate the review file** — prepend a `## Debug Notes (Session {SessionId})` section at the top of the review file with:
   - Which checklist items have evidence (proven/disproven/inconclusive)
   - Relevant data excerpts from the session
   - Date of the cross-reference check
4. **Create follow-up plans** if the cross-reference reveals:
   - A review item is definitively disproven (the fix didn't work) → create a fix plan
   - New issues discovered while investigating the review item → create separate plans

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
- How many tokens where wasted becasue the agent had bad instructions? Can we optimize this?
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
- When creating plans from `review-ux.md` findings, list the screenshots referenced in `review-ux.md` in the plan's `## Evidence` section. Screenshots are stored at `{WorkDir}/.ivy/tests/screenshots/` and videos at `{WorkDir}/.ivy/tests/videos/`. Include the full absolute path for each relevant screenshot (e.g., `D:\Temp\IvyAgentTestManager\2026-03-17\00257-Campaign-Dashboard\Test.Campaign-Dashboard\.ivy\tests\screenshots\01-initial-load.png`). The `review-ux.md` file uses `### [filename.png]` headings — parse these filenames and construct the full path using `{WorkDir}/.ivy/tests/screenshots/{filename}`. Include relevant video paths in the `## Evidence` section when the issue involves interactions or animations. Only include screenshots and videos relevant to the specific issue being planned.

#### Hallucinations (DIRECT EDIT — no plans)

When `langfuse-hallucinations.md` reports hallucinated APIs, **directly update** `D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared\Docs\05_Other\Hallucinations.md` instead of creating a plan. This is an exception to the read-only rule.

Steps for each hallucination:
1. Check if the hallucinated API already has a section in Hallucinations.md — if yes, add the session UUID to the "Found In" list
2. If new, add a new `##` section following the existing format (Hallucinated API code block, Error, Correct API, Found In)
3. Check if a refactoring rule could prevent it (see Memory/RefactoringRules.md) — if a rule is warranted, create a plan for that separately
4. Check `D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared\Docs` for missing or unclear documentation
5. Check if samples cover the misused pattern

**Every time Hallucinations.md is edited, also:**
- **Prune stale entries**: Check whether each existing section's hallucinated API has since been added to the framework (i.e., is no longer a hallucination). If the API now exists, either remove the section or mark it `— now supported`. Verify by searching the Ivy-Framework source.
- **Rerank all `##` sections** by descending frequency using these rules:
  - Count each unique UUID in "Found In" as 1
  - `(multiple sessions)` = 3
  - `(session not yet recorded)` = 1
  - Entries with "appeared in ALL sub-tasks" get +2 bonus
  - Entries with no "Found In" section = 0
  - Ties: preserve existing relative order (stable sort)
  - `— now supported` entries always go to the bottom regardless of count

#### System Reminders
- If `langfuse-system-reminders.md` shows reminders firing, check:
  - Are reminders firing excessively? (>3 of same type = agent likely stuck)
  - Did the agent change behavior after the reminder? If not, the analyser text may need improvement
  - Check the analyser source in `D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent\Agents\Analysers\` for prompt quality
  - Consider if the analyser threshold is too low (firing too early) or too high (firing too late)

### 4. Create Plan Files

For each actionable finding, create a plan file in `D:\Repos\_Ivy\.plans\`.

- Read the counter from `.counter` (default 200 if missing), allocate IDs, increment
- Format: `<ID>-<RepositoryName>-<LEVEL>-<Title>.md`
- Repository names: `IvyAgent`, `IvyConsole`, `IvyFramework`, `General`
- LEVEL (priority/criticality):
  - **CRITICAL** — Must be fixed immediately, blocks work or causes severe issues (build failures, crashes, data loss)
  - **NICETOHAVE** — Improves functionality but not urgent (hallucinations, missing docs, workflow improvements)
  - **NITPICK** — Minor polish, cosmetic fixes, or low-priority refinements (cosmetic issues, minor doc tweaks, formatting)
- Before creating a plan, search existing plans to avoid duplicates — update existing plans if they partially cover the finding
- Read `{WorkDir}/.ivy/plans.md` if it exists — this lists plans created in previous runs of this script. Skip creating plans already listed there
- After creating new plans, append their paths to `{WorkDir}/.ivy/plans.md` (create the file if it doesn't exist) using this format:
  ```markdown
  # Created Plans

  - D:\Repos\_Ivy\.plans\268-Scripts-NICETOHAVE-Example.md
  ```

Plan format:

```markdown
---
source: {WorkDir}/.ivy/
session: {SessionId}
workflow: <workflows used in this session, from langfuse-workflows.md>
references: <reference connection files read, from langfuse-reference-connections.md>
---
# [Title]

## Problem

[What went wrong, with evidence from review files]

## Evidence

[Optional — absolute paths to relevant screenshot(s) from {WorkDir}/.ivy/tests/screenshots/ that demonstrate the problem. Only include when the plan was derived from screenshot/UX analysis.]

## Solution

[Concrete steps — include file paths, code patterns, API names]

## Clean up

1. Commit
```

### IvyFramework Verification

When a plan targets **IvyFramework** (queue = `IvyFramework`) **and the change affects visual/UI behavior** (e.g., fixing a widget bug, changing layout, adding a new component), include a `### Verification` section after the commit instructions with instructions to run **IvyFeatureTester.ps1**.

**Do NOT add verification for non-visual changes** such as documentation updates, FAQ entries, analyser error messages, refactoring rules, or code-only fixes that don't affect rendered output.

```markdown
### Verification

After committing the fix, use **IvyFeatureTester.ps1** to verify the changes visually:

\```powershell
cd D:\Repos\_Ivy
D:\Repos\_Personal\Scripts\AF2\IvyFeatureTester.ps1 "Commit <COMMIT_ID>: <description of what to test>. Test with <specific test scenario>."
\```

Replace `<COMMIT_ID>` with the actual commit hash from the fix commit above.
```

The prompt should describe the expected behavior and suggest a concrete test scenario appropriate for the change.

### Rules

- **Everything must be expressed as plans** — FAQ edits, doc improvements, workflow fixes
- **Exception**: Hallucinations.md updates are applied directly (not as plans) — see the Hallucinations section above
- ONE issue per plan file
- Plans must include all paths and information for an LLM coding agent to execute end-to-end
- Keep plans short and concise
- Do NOT modify any source code directly — only read files and create plan files. **Exception**: `Hallucinations.md` may be edited directly.
- Missing review files are not failures — analyze what's available
- When annotating review files in `.plans\review\`, preserve the original content — only prepend notes at the top
- If a review file's checklist is fully verified (all items proven), move it to `.plans\review\verified\`
- Review cross-references should be concise — link to evidence, don't copy large data blocks

## Finally 

Give that you are an orchestrator - feel free to make improvements to:

D:\Repos\_Personal\Scripts\AF2\IvyAgentReviewBuild
D:\Repos\_Personal\Scripts\AF2\IvyAgentReviewLangfuse
D:\Repos\_Personal\Scripts\AF2\IvyAgentReviewSpec
D:\Repos\_Personal\Scripts\AF2\IvyAgentReviewTests

According to the the D:\Repos\_Personal\Scripts\AF2\.shared\Firmware.md instructors if you feel that the output from these skills can be improved for you to optimize your future performance. 