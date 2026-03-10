# IvyAgentReviewLangfuse

Analyze Langfuse telemetry data from an Ivy Agent session and produce structured review files.

## Context

The Firmware header provides:
- `WorkDir` — the Ivy project root (contains `.csproj` and `.ivy/`)
- `SessionId` — the Langfuse session ID
- `LangfuseDir` — absolute path to the downloaded langfuse data folder

The langfuse folder structure is:
```
{LangfuseDir}/
├── 001_{TraceName}/
│   ├── trace.json
│   ├── 001_{Type}_{Name}.json
│   ├── 002_{Type}_{Name}.json
│   └── ...
├── 002_{TraceName}/
│   └── ...
```

Each observation JSON has a structure like:
- `type`: "GENERATION" or "SPAN"/"EVENT"
- `startTime`: ISO timestamp
- `input`: object containing either:
  - `message`: object with `$type` (e.g. "WriteFileMessage", "BuildProjectResultMessage", "WorkflowStartMessage")
  - `toolName` + `request`/`response` (for IvyQuestion, IvyDocs, WebFetch etc.)
  - `feedback` (for ToolFeedback events)
- `output`: generation output (tool calls, text)
- `usageDetails`: token counts
- `metadata`: { finishReason, ... }

## Execution Steps

### 1. Validate

- Confirm `LangfuseDir` exists and contains trace folders
- Confirm `WorkDir` exists

### 2. Run Tools & Generate Reports

Use the PowerShell tools in `/Tools/` to query the langfuse data. Each tool takes `-LangfuseDir` as parameter.

Generate these files in `{WorkDir}/.ivy/`:

#### `langfuse-timeline.md`

Compact session timeline. Use `Get-Timeline.ps1`.

```markdown
# Session Timeline: {SessionId}

## Trace: {TraceName} ({latency}s)

| # | Time | Type | Workflow | Preview |
|---|------|------|----------|---------|
| 001 | 12:30:01 | GEN | Build>Code | WriteFile, BuildProject |
| 002 | 12:30:05 | SPAN | Build>Code | IvyQuestion: "How to..." |
```

#### `langfuse-hallucinations.md`

Build errors caused by hallucinated APIs/patterns. Use `Get-Hallucinations.ps1`.

Look for the pattern: IvyQuestion answer → WriteFile → Build FAIL. When a build fails after an IvyQuestion-informed write, the question answer likely contained hallucinated APIs.

```markdown
# Hallucination Analysis: {SessionId}

## Suspected Hallucinations

### Hallucination N

**IvyQuestion**: "{question text}"
**Answer used in**: `{file path}`
**Build error**: {error code}: {message}
**Analysis**: [What was hallucinated — wrong API, wrong method signature, non-existent class, etc.]

## Summary

| Metric | Count |
|--------|-------|
| Total IvyQuestions | N |
| Questions followed by build errors | N |
| Unique hallucinated APIs | N |
```

#### `langfuse-questions.md`

All questions asked during the session (IvyQuestion and WebFetch+AnswerAgent). Use `Get-IvyQuestions.ps1`.

The tool returns a `Source` field: `IvyQuestion` (local doc lookup) or `AnswerAgent` (WebFetch question answered by LLM).

**Important**: Only label errors as "ToolFeedback" when an actual `EVENT_ToolFeedback` observation exists (with `input.feedback`). AnswerAgent failures are NOT ToolFeedback — they are LLM processing errors. Use the tool's `Success`/`Error` fields to determine status; do not infer status from other events in the timeline.

```markdown
# IvyQuestion Log: {SessionId}

## Questions

### Q1: {question text}

**Source**: IvyQuestion / AnswerAgent
**Status**: ✅ Success / ❌ Failed
**Answer length**: N chars
**Error**: {if failed}

### Q2: ...
```

#### `langfuse-workflows.md`

All workflows used. Use `Get-Workflows.ps1`.

Include absolute paths to workflow files. Workflow files live in:
- `D:\Repos\_Ivy\Ivy\Ivy.Internals\Workflows\` — look for `{workflowName}.workflow`
- Also check reference files read during the workflow

```markdown
# Workflows: {SessionId}

## {WorkflowName}

**Status**: ✅ Success / ❌ Failed
**File**: `{absolute path to .workflow file}`
**States**: state1 → state2 → state3
**References read**:
- `{absolute path}` ({chars} chars)

## Summary

| Workflow | Status | States |
|----------|--------|--------|
```

#### `langfuse-reference-connections.md`

Reference connections used. Use `Get-ReferenceConnections.ps1`.

Reference connection files live in `D:\Repos\_Ivy\Ivy\connections\`.

```markdown
# Reference Connections: {SessionId}

## Connections Used

| Connection | Local Path |
|------------|-----------|
| {name} | `D:\Repos\_Ivy\Ivy\connections\{name}\...` |
```

#### `langfuse-docs.md`

All IvyDocs read by the agent. Use `Get-DocsRead.ps1`.

```markdown
# Docs Read: {SessionId}

## Documents

| # | Trace | Path | Status | Size |
|---|-------|------|--------|------|
| 1 | 001_Agent | AGENTS.md | ✅ 14718 chars | |
| 2 | 001_Agent | docs/Widgets/Button.md | ❌ 404 | |

## Summary

| Metric | Count |
|--------|-------|
| Total doc reads | N |
| Successful | N |
| Failed (404) | N |
| Total chars read | N |
```

#### `langfuse-build-errors.md`

All build errors throughout the session. Use `Get-BuildErrors.ps1`.

```markdown
# Build Errors: {SessionId}

## Build #1 ({observation file}) — ❌ FAILED

### {relative path}
- `CS1234:42` — {error message}
- `CS5678:10` — {error message}

**Preceding writes**:
- `{file path}`

## Build #2 — ✅ OK

## Summary

| Metric | Count |
|--------|-------|
| Total builds | N |
| Failed builds | N |
| Unique error codes | CS1234, CS5678 |
```

### 3. Summary

Present the user with:
- Session ID
- Number of traces
- Timeline highlights (total generations, token usage)
- Build error count
- Hallucination count
- Workflow summary
- IvyQuestion summary

### Rules

- All output goes to `{WorkDir}/.ivy/`
- Use the PowerShell tools — they are your primary data access layer
- If a tool doesn't exist or doesn't return what you need, create or improve it
- Keep reports factual — only flag hallucinations where the evidence chain is clear
- Include absolute paths wherever files are referenced
