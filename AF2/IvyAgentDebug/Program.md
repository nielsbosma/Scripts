# IvyAgentDebug

Analyze review data from an Ivy Agent session and generate actionable improvement plans via the Tendril Inbox.

## Context

By the time you run, these review scripts have already completed and produced files in `{WorkDir}/.ivy/`:

- **ReviewBuild** → `review-build.md`
- **ReviewLangfuse** → `langfuse-session-status.md`, `langfuse-timeline.md`, `langfuse-build-errors.md`, `langfuse-docs.md`, `langfuse-hallucinations.md`, `langfuse-questions.md`, `langfuse-reference-connections.md`, `langfuse-workflows.md`, `langfuse-system-reminders.md`
- **ReviewSpec** → `review-spec.md`
- **ReviewTests** → `review-tests.md`, `review-ux.md`

Read about the important paths and files in `../.shared/Paths.md`

Read `/Memory/Langfuse.md` for Langfuse JSON structure reference if you need to inspect raw data.

## Execution Steps

### 1. Read All Reviews

Read every review file in `{WorkDir}/.ivy/`:

- `.ivy/spec.md` — the original spec
- `.ivy/review-build.md` — build review
- `.ivy/review-spec.md` — spec compliance review
- `.ivy/review-tests.md` — test results, project fixes applied, external issues
- `.ivy/review-ux.md` — UX/screenshot review
- `.ivy/langfuse-session-status.md` — session completion status (Complete/Failed/PrematureStop) and diagnosis
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

Also check for `.ivy/feedback.md` — this contains free-form feedback from the user. Like annotations, this feedback should be treated with **highest priority** and should influence your analysis.

Check the logs:

{WorkDir}/.ivy/sessions/<session-id>/
  <session-id>-client-verbose.log
  <session-id>-client-output.log
  <session-id>-server-verbose.log
  <task-trace-id>-client-verbose.log
  <task-trace-id>-server-verbose.log
  langfuse/

Anything that stands out that we should look into?

### 2. Investigate & Identify Issues

Analyze all the collected data to find issues and improvements for the Ivy Agent ecosystem.

This can include:

- **Ivy-Framework**: Fix bugs, update APIs to match hallucinations, add missing APIs the agent struggled to find
- **Ivy-Agent**: Fix bugs, improve token usage, performance, tool instructions, persona usage
- **Token waste**: Bad instructions causing unnecessary token consumption
- **One-shot failures**: Review `<session-id>-client-output.log` for signs the session wasn't a clean one-shot
- **Agent clients**: Bugs in Ivy Studio, Tui, NonInteractive
- **Documentation**: Strengthen docs where agent got confused
- **Workflows**: Improve agent workflows and reference connections
- **Analysers**: Add compile-time checks to `Ivy.Analyser` for common runtime errors

For each issue, determine:
1. **What went wrong** — with evidence from review files
2. **Root cause** — hallucination vs missing package vs framework bug vs user code bug
3. **Which project** it belongs to (Framework, Agent, Tendril, Console, Mcp, Scripts, or leave blank for auto-detection)
4. **Severity** — Critical, Bug, NiceToHave

#### Hallucinations (DIRECT EDIT — no inbox)

When `langfuse-hallucinations.md` reports hallucinated APIs, **directly update** `D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared\Docs\05_Other\Hallucinations.md` instead of creating an inbox item. This is an exception to the read-only rule.

Steps for each hallucination:
1. Check if the hallucinated API already has a section in Hallucinations.md — if yes, add the session UUID to the "Found In" list
2. If new, add a new `##` section following the existing format (Hallucinated API code block, Error, Correct API, Found In)
3. Check if a refactoring rule could prevent it (see Memory/RefactoringRules.md) — if a rule is warranted, create an inbox item for that separately

**Every time Hallucinations.md is edited, also:**
- **Prune stale entries**: Check whether each existing section's hallucinated API has since been added to the framework. If the API now exists, either remove the section or mark it `— now supported`. Verify by searching the Ivy-Framework source.
- **Rerank all `##` sections** by descending frequency using these rules:
  - Count each unique UUID in "Found In" as 1
  - `(multiple sessions)` = 3
  - `(session not yet recorded)` = 1
  - Entries with "appeared in ALL sub-tasks" get +2 bonus
  - Entries with no "Found In" section = 0
  - Ties: preserve existing relative order (stable sort)
  - `— now supported` entries always go to the bottom regardless of count

#### IvyMcp Issues (GitHub Issues — no inbox)

When a finding belongs to **IvyMcp** (IvyDoc, IvyQuestion, hallucinations from MCP knowledge base), **create a GitHub issue** in `Ivy-Interactive/Ivy-Mcp` instead of an inbox item.

Steps:
1. Determine if the finding is IvyMcp-related by checking:
   - `langfuse-questions.md` — wrong or incomplete IvyQuestion answers
   - `langfuse-docs.md` — IvyDoc 404s or missing documentation served by MCP
   - `langfuse-hallucinations.md` — hallucinations where the source is IvyMcp (check raw IvyQuestion JSON per Memory/IvyMcpHallucinationSource.md)

2. Create a GitHub issue using:
   ```bash
   gh issue create --repo Ivy-Interactive/Ivy-Mcp \
     --title "<concise title>" \
     --body "$(cat <<'EOF'
   ## Problem

   <description with evidence from review files>

   ## Evidence

   - Session: <session-id>
   - Source: <which review file identified this>

   ## Suggested Fix

   <concrete steps if known>
   EOF
   )"
   ```

3. Use labels if applicable: `--label "bug"` for broken behavior, `--label "knowledge-base"` for wrong answers/hallucinations from MCP.

### 3. Write to Tendril Inbox

For each actionable finding (that isn't a Hallucination.md edit or IvyMcp GitHub issue), create a `.md` file in `D:\Tendril\Inbox\`.

**File naming**: `<short-descriptive-name>.md` (e.g., `infrastructure-analyser-ineffective.md`, `enum-display-names.md`)

**File format**:

```markdown
---
project: <ProjectName or leave out for auto-detection>
sourcePath: <absolute path to the test working directory ({WorkDir})>
---
<Full description of the issue and proposed solution>

Include:
- What went wrong (with evidence from review files)
- Concrete steps to fix (file paths, code patterns, API names)
- Relevant screenshots/video paths if from UX analysis
- Session ID for traceability
```

The `project` field should match a project in Tendril's config.yaml (Framework, Agent, Tendril, Console, Mcp, Scripts). Omit the frontmatter entirely if you want Tendril to auto-detect the project.

Always include `sourcePath: {WorkDir}` in inbox frontmatter for traceability back to the test session.

**One issue per file.** Keep descriptions concise but include enough context (file paths, code patterns) for a coding agent to execute end-to-end.

#### Evidence References

- **When referencing local files** in the description, use full absolute paths (e.g., `D:\Repos\_Ivy\Ivy-Framework\src\Ivy\Widgets\Button.cs`)
- **When referencing screenshots**, include the full path from `{WorkDir}/.ivy/tests/screenshots/`. The `review-ux.md` file uses `### [filename.png]` headings — parse these and construct the full path using `{WorkDir}/.ivy/tests/screenshots/{filename}`
- **When referencing videos**, include paths from `{WorkDir}/.ivy/tests/videos/`

### 4. Write Summary Log

Write a summary to `{WorkDir}/.ivy/plans.md` listing what was created:

```markdown
# IvyAgentDebug Results

- D:\Tendril\Inbox\infrastructure-analyser-ineffective.md (Agent: Infrastructure analyser ignoring reminders)
- D:\Tendril\Inbox\enum-display-names.md (Framework: Enum display in .ToOptions())
- https://github.com/Ivy-Interactive/Ivy-Mcp/issues/127 (IvyMcp: IvyQuestion NotFound for Fragment rendering)
- Hallucinations.md: Added session UUID to Fragment.ForEach entry
```

### Rules

- **One issue per inbox file**
- Inbox files must include all paths and information for an LLM coding agent to execute end-to-end
- Keep descriptions concise but actionable
- Do NOT modify any source code directly — only read files and create inbox items. **Exceptions**: `Hallucinations.md` may be edited directly.
- **IvyMcp findings must be created as GitHub issues in `Ivy-Interactive/Ivy-Mcp`** — never as inbox items
- **Hallucination findings go directly to Hallucinations.md** — never as inbox items
- Missing review files are not failures — analyze what's available
- **!IMPORTANT: Plans should rarely propose changes to `AGENTS.md` or Persona `.md` files. These files are read by all flows and must remain tight and handcrafted. Instead, look for a workflow file, analyser, tool instruction, or other targeted file to modify.**

## Finally

Given that you are an orchestrator - feel free to make improvements to:

D:\Repos\_Personal\Scripts\AF2\IvyAgentReviewBuild
D:\Repos\_Personal\Scripts\AF2\IvyAgentReviewLangfuse
D:\Repos\_Personal\Scripts\AF2\IvyAgentReviewSpec
D:\Repos\_Personal\Scripts\AF2\IvyAgentReviewTests

According to the D:\Repos\_Personal\Scripts\AF2\.shared\Firmware.md instructions if you feel that the output from these skills can be improved for you to optimize your future performance.
