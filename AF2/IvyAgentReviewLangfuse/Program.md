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

### 1. Validate & Prepare

- Confirm `LangfuseDir` exists and contains trace folders
- Confirm `WorkDir` exists
- Run `Expand-EmbeddedObservations.ps1 -LangfuseDir` to extract any observations embedded in trace.json into separate files (required by all other tools)
- Run `Get-SessionStatus.ps1 -LangfuseDir` to determine session completeness
- If session status is `PrematureStop` or `Failed`, set `$incomplete = true` — you will add a banner to each generated report

### 2. Run Tools & Generate Reports

Use the PowerShell tools in `/Tools/` to query the langfuse data. Each tool takes `-LangfuseDir` as parameter.

**Incomplete session handling:** If `$incomplete` is true, add the following banner at the top of EVERY generated report file (right after the H1 heading):

```markdown
> **Warning: Session ended prematurely** — data may be incomplete. Status: {status}, Reason: {stopReason}
```

If a tool returns empty or minimal data for an incomplete session, still generate the report file with the banner and a note: "No data available — session ended before this data was generated." This ensures downstream tools (IvyAgentDebug) always have report files to work with.

Generate these files in `{WorkDir}/.ivy/`:

#### `langfuse-session-status.md`

Session status report. Always generated first, using `Get-SessionStatus.ps1`.

```markdown
# Session Status: {SessionId}

**Status**: Complete / Failed / PrematureStop
**Stop Reason**: {reason from Get-SessionStatus}
**Last Observation**: {time} — {preview}
**Last Workflow State**: {state}
**Generations**: {count}
**Tokens**: {input} in / {output} out

## Workflows
| Workflow | Status |
|----------|--------|
| {name} | Finished / Active (unfinished) / Failed |

## Diagnosis (PrematureStop/Failed only)

{If incomplete, analyze the last few observations to determine what the agent was doing when it stopped.
Look at the last observation preview, the last workflow state, and any error indicators.
Provide a brief analysis of the likely cause.}
```

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

**Tool output format**: Each question produces TWO rows with the same `ObservationFile`:
1. **Request** row (`Direction=Request`): Contains the `Question` text; `Success`, `AnswerLength`, and `Error` fields are null
2. **Response** row (`Direction=Response`): Contains `Success`, `AnswerLength`, and `Error` fields; `Question` field is null

**Processing logic**: Group rows by `ObservationFile`. For each question, extract the `Question` text from the Request row and the status fields (`Success`, `AnswerLength`, `Error`) from the Response row.

**Important**: Only label errors as "ToolFeedback" when an actual `EVENT_ToolFeedback` observation exists (with `input.feedback`). AnswerAgent failures are NOT ToolFeedback — they are LLM processing errors. Use the tool's `Success`/`Error` fields to determine status; do not infer status from other events in the timeline.

**Status mapping**: A question is successful ONLY when the Response row has `Success=true` (case-insensitive, as PowerShell returns boolean `True`/`False`) AND `AnswerLength > 0`. ALL other cases — `Success=false`, no Success value, `AnswerLength=0`, empty answer, error, timeout — are **failed**. Use only two statuses: `✅ Success` or `❌ Failed`. Do not use any other status like "❓ No response".

```markdown
# IvyQuestion Log: {SessionId}

## Questions

### Q1: {question text}

**Source**: IvyQuestion / AnswerAgent
**Status**: ✅ Success / ❌ Failed
**Answer length**: N chars
**Error**: {if failed, include error message; for no response use "No answer returned"}

### Q2: ...

## Summary

| Metric | Count |
|--------|-------|
| Total IvyQuestions | {total} |
| Successful | {count where Status = ✅ Success} |
| Failed | {count where Status = ❌ Failed} |
| Total answer chars | {sum of answer lengths from successful questions} |
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

#### `langfuse-gettypeinfo.md`

GetTypeInfo tool usage analysis. Use `Get-TypeInfoUsage.ps1`.

```markdown
# GetTypeInfo Usage: {SessionId}

## Lookups

### Lookup N

**Search**: `{search term}`
**Type**: Type / Method
**Trace**: {TraceName}
**Status**: ✅ {totalMatches} matches / ❌ Failed
**Results**: {comma-separated type names}
**Warning**: {if any}

## Patterns

### Repeated Searches
{List search terms that appear more than once, with count}

### Failed Lookups
{List searches with success=false or totalMatches=0}

### Method Searches
{List all Method-type searches}

## Summary

| Metric | Count |
|--------|-------|
| Total GetTypeInfo calls | N |
| Successful | N |
| Failed / 0 results | N |
| Unique search terms | N |
| Type searches | N |
| Method searches | N |
| Repeated searches | N |
```

#### `langfuse-system-reminders.md`

System reminder events fired by context window analysers. Use `Get-SystemReminders.ps1`.

```markdown
# System Reminders: {SessionId}

## Reminders

### Reminder N

**Time**: {timestamp}
**Analyser**: {analyser class name}
**Message**: {reminder text}
**Next Action**: {preview of what agent did next}

## Summary

| Analyser | Count |
|----------|-------|
| RepeatedBuildFailureAnalyser | N |
| BuildErrorScopeAnalyser | N |
| RepeatedToolFeedbackAnalyser | N |
```

#### `langfuse-refactorings.md`

CSharp refactoring rules applied during the session. Use `Get-CSharpRefactorings.ps1`.

```markdown
# CSharp Refactorings: {SessionId}

## Refactorings

| Trace | File | Rules Applied | Count |
|-------|------|---------------|-------|
| 001_... | Components/Button.cs | ReplaceInvalidColors, RemoveComments | 2 |

## Summary

| Metric | Value |
|--------|-------|
| Total files refactored | N |
| Total rule applications | N |
| Most frequent rules | Rule1 (N), Rule2 (N), ... (top 5) |
| High rule-count files | file.cs (N rules) |
```

### 3. Summary

Present the user with:
- Session ID
- **Session status** (Complete / Failed / PrematureStop) and stop reason
- Number of traces
- Timeline highlights (total generations, token usage)
- Build error count
- Hallucination count
- Workflow summary
- IvyQuestion summary
- CSharp refactoring summary

### Rules

- All output goes to `{WorkDir}/.ivy/`
- Use the PowerShell tools — they are your primary data access layer
- If a tool doesn't exist or doesn't return what you need, create or improve it
- Keep reports factual — only flag hallucinations where the evidence chain is clear
- Include absolute paths wherever files are referenced
