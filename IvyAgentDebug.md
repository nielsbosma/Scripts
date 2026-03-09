Read D:\Repos\_Personal\Scripts\PlanContext.md for shared context (folders, Langfuse steps, etc.).

## Getting started

[ ] Get the IVY_AGENT_DEBUG_FOLDER path. This is typically a User-level environment variable. Fetch it using two sequential calls to avoid bash interpolation issues with PowerShell variables:
```
powershell -Command '[Environment]::GetEnvironmentVariable("IVY_AGENT_DEBUG_FOLDER", "User")'
```
If that returns empty, try Machine scope:
```
powershell -Command '[Environment]::GetEnvironmentVariable("IVY_AGENT_DEBUG_FOLDER", "Machine")'
```
Note: The standard `echo %VAR%` and `$env:VAR` approaches may not work in all shell contexts. Always use the .NET Environment API above.

Log files in the session folder are prefixed with a trace ID to disambiguate logs per connection:

```
IVY_AGENT_DEBUG_FOLDER\<session-id>\
  <session-id>-client-verbose.log      ← root client ILogger output
  <session-id>-client-output.log       ← root interactive TUI output (only with --log-output)
  <session-id>-server-verbose.log      ← root server logs
  <task-trace-id>-client-verbose.log   ← per sub-task client logs (one per spawned task)
  <task-trace-id>-server-verbose.log   ← per sub-task server logs (one per spawned task)
```

The root connection uses session-id as its trace ID, so the root files are prefixed with the session ID. Each sub-task gets a unique trace ID (`TaskMessage.TraceId`), so its client and server logs use that as the prefix. All files live in the same session folder.

We should already have at least `<session-id>-client-verbose.log` and `<session-id>-server-verbose.log` in that folder. If they're missing, note this but proceed with Langfuse analysis — client logs are supplementary and not required for most debugging tasks.

If the session spawned sub-tasks, there will be additional `<task-trace-id>-*` log files. You can correlate these with Langfuse traces since the task trace ID is the same GUID used for the sub-agent's Langfuse trace.

[ ] Check if there's a subfolder named "langfuse" in the session folder. If not we first need to fetch the session trace from Langfuse.

This is done using the following CLI command:

```
ivy-agent langfuse session get {{SESSION_ID}}
```

IMPORTANT: Always use the `ivy-agent` CLI tool (which should be in your PATH). Do NOT use `dotnet run` — the server likely binds to a port that's already in use, and it's not designed for CLI-only invocations via `dotnet run`.

We now get files in the following pattern:

IVY_AGENT_DEBUG_FOLDER\{{SESSION_ID}}\langfuse\XXX_<trace-name>\XXX_<observation-type>_<observation-name>.json
IVY_AGENT_DEBUG_FOLDER\{{SESSION_ID}}\langfuse\XXX_<trace-name>\trace.json

The session can have multiple traces, each with multiple observations. If there are multiple traces we should ask the user which trace they want to investigate, providing the trace names.

We should only investigate one trace at a time, so once the user has selected a trace we should focus on the files related to that trace for the rest of the analysis.

[ ] **Quick session timeline**: Run this to get a high-level overview of what happened in the trace:

```
ivy-agent langfuse session timeline --session-id <session-id> -c
```

You can also use a trace ID directly (the session will be resolved automatically):
```
ivy-agent langfuse session timeline --trace-id <trace-id> -c
```

This prints a table per trace: filename, latency, message count, token counts, and a preview of the output or message type.

**Flags:**
- `--session-id` / `-s`: Session ID to display timeline for.
- `--trace-id` / `-t`: Trace ID to resolve session from (if `--session-id` is not provided). Can also be used together with `--session-id` to filter to a specific trace.
- `--compact` / `-c`: Omit UI noise events (UIStatusMessage, UITokenUsageMessage, UIChatMessage). Always use this by default — it reduces output from hundreds of lines to a manageable overview while keeping all summary counters intact.
- `--filter` / `-f`: Comma-separated observation name filters (e.g. `IvyDocs,IvyQuestion`). Shows only observations whose file name contains any of the filter values. Useful for focusing on specific observation types like `--filter IvyDocs,IvyQuestion` or `--filter BuildProjectResultMessage`.
- `--build-errors`: Show only the build error progression — each build result with its errors and the file writes that preceded it. Use this when investigating build failures to quickly see what code caused which errors.

### Workflow investigations

If the session involves a workflow (look for `WorkflowStartMessage` events), read the workflow source code and prompt templates early. Understanding the intended workflow flow is critical for diagnosing why the agent did or didn't take expected actions.

Workflow source files are organized in subdirectories:
`D:\Repos\_Ivy\Ivy\Ivy.Internals\Workflows\<Category>\<WorkflowName>\`

Common categories: Projects, Internal, etc. Use glob patterns to find them:
`**/Workflows/**/<WorkflowName>Workflow.cs`

Each workflow has a `.cs` file and a `Prompts\` subfolder with the markdown templates that drive agent behavior.

Quick Reference: JSON Path Cheat Sheet for Observations

$.type                          → "EVENT" or "GENERATION"
$.name                          → observation name
$.traceId                       → trace correlation ID
$.parentObservationId           → parent span ID
$.input.content                 → (EVENT) document/data content
$.input.messages[*].role        → (GENERATION) message roles
$.input.messages[0].contents[0].text  → (GENERATION) system prompt
$.input.tools[*].function.name  → (GENERATION) available tool names
$.output                        → model response text
$.metadata.finishReason         → stop reason
$.model                         → model name
$.modelParameters               → temperature, maxTokens, etc.
$.latency                       → seconds elapsed
$.usageDetails                  → token counts
$.startTime / $.endTime         → timing
$.level                         → DEFAULT / WARNING / ERROR
$.statusMessage                 → error details

### BuildProjectResultMessage Structure
$.input.message.success              → build success boolean
$.input.message.buildResults[]       → per-project results array
$.input.message.buildResults[].relativePath    → source file path
$.input.message.buildResults[].buildErrors[]   → array of errors
$.input.message.buildResults[].buildErrors[].message  → error message
$.input.message.buildResults[].buildErrors[].line     → line number
$.input.message.buildResults[].buildErrors[].errorCode → CS error code

These files are large so use the jq CLI to query the information you need.

### Observation Filenames

Observation filenames have bracket characters normalized to underscores (e.g., `LocalRequest_in_` instead of `LocalRequest[in]`), so standard shell globbing works without special escaping.

### Workflow Debugging Recipes

**List all workflow transitions:**
```
jq -s '[.[] | select(.name | test("WorkflowTransition"))] | .[].input.message.prompt' *.json
```

**Show question sequences:**
```
jq '.input.message.initialToolCalls[].questions[] | {key, question, defaultValue, options: [.options[].label]}' *WorkflowTransitionMessage*.json
```

**Show agent's submitted values:**
```
jq '{name: .name, output: .output}' *GENERATION*.json
```

**Show all tool feedback errors (workflow issues):**
```
jq 'select(.name | test("ToolFeedback")) | {name: .name, tool: .input.toolName, feedback: .input.feedback}' *.json
```

**Show build error progression:**
```
jq 'select(.name | test("WorkflowTransitionMessage")) | select(.input.message.prompt | test("Build Errors")) | .input.message.prompt[0:300]' *.json
```

**Show failed bash commands:**
```
jq 'select(.name | test("BashResultMessage")) | select(.input.message.success == false) | {name: .name, exitCode: .input.message.exitCode, error: .input.message.error[0:200]}' *.json
```

**Show file writes (what was generated):**
```
jq 'select(.name | test("WriteFileMessage")) | .input.message.filepath' *.json
```

**Show user's initial prompt:**
```bash
jq -r '.input.messages[1].contents[0].text // .input.messages[1].content' 002_GENERATION_PersonaAgent.json
```

**Reference vs Generated File Diff**
Compare a workflow reference file against what the agent actually wrote:
```bash
jq -r '.input.message.content' *WorkflowReferenceResultMessage*.json > /tmp/ref.cs
jq -r '.input.message.content' *WriteFileMessage*.json > /tmp/gen.cs
diff /tmp/ref.cs /tmp/gen.cs
```

### Build Error Recipes

**Extract all build errors across all builds:**
```bash
for f in *BuildProjectResultMessage*.json; do echo "=== $f ===" && jq '[.input.message.buildResults[]?.buildErrors[]? | {message, line}]' "$f"; done
```

**Show build success/failure summary:**
```bash
for f in *BuildProjectResultMessage*.json; do echo "=== $f ===" && jq '{success: .input.message.success, errorCount: [.input.message.buildResults[]?.buildErrors[]?] | length}' "$f"; done
```

**Show IvyQuestion Q&A pairs:**
```bash
for f in *IvyQuestion*.json; do echo "=== $f ===" && jq '{question: .input.question, answer: .input.answer[0:300]}' "$f"; done
```

### Hallucination-Finding Recipe

To find potential Ivy Framework hallucinations, correlate build errors with the code the agent wrote:

**1. Find builds with errors:**
```bash
for f in *BuildProjectResultMessage*.json; do jq -r 'select(.input.message.success == false) | "=== \(.name // input_filename) ===\n" + ([.input.message.buildResults[]?.buildErrors[]? | "\(.relativePath):\(.line) \(.errorCode): \(.message)"] | join("\n"))' "$f"; done
```

**2. Show file writes before each failed build:**
```bash
jq -s '[.[] | {name, type: (if .name | test("WriteFile") then "WRITE" elif .name | test("BuildProject") then "BUILD" else null end), file: .input.message.filepath?, success: .input.message.success?}] | [.[] | select(.type != null)]' *.json
```

**3. Check IvyQuestion/IvyDocs answers that preceded the error** — the agent may have received correct guidance but hallucinated the API anyway, or the answer itself may have been misleading.

### LSP Coordinate Systems

Build errors, grep results, and LSP results all use **1-based** line/column in LLM-facing output. However, `LspMessage` stores **0-based** coordinates internally (matching the LSP protocol). When examining raw Langfuse JSON for LSP events, `$.input.message.line` and `$.input.message.character` are 0-based — add 1 to match editor line numbers.

### Debugging Tips

**Tool call issues:** When investigating problems with tool calls (wrong arguments, failed calls, unexpected behavior):
1. Check `EVENT_LocalRequest` observations — these capture the processed tool arguments as sent to the server for locally handled tools (WebSearch, WebFetch, IvyDocs, IvyQuestion). Use `jq '.input'` to see the actual request payload.
2. Check the tool schema in GENERATION files with `jq '.input.tools[] | select(.function.name == "ToolName") | .function.parameters'` — schema mismatches (e.g. optional params marked as required, wrong types) are a common root cause of LLM tool call issues.
3. Cross-reference the `EVENT_LocalResponse` to see what the tool returned.

## Tasks

The user has asked us to investigate the session with the following prompt:

---
{{PROMPT}}
---

## Task: Hallucinations

In some cases we discover an API hallucination by the agent about the Ivy Framework.

We want to document any hallucinations you find in D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared\Docs\05_Other\Hallucinations.md together with the solution.

Find you find hallucinations by finding BuildResultMessage that contains build errors, then looking at the question sequences leading up to that message to find out what the agent misunderstood about the API.

We only want to document hallucinations related to the Ivy Framework, not general LLM misunderstandings about programming or other APIs.

Not all build errors indicate Ivy Framework hallucinations. Common non-hallucination causes:
- Missing assembly references (project configuration issues)
- Missing NuGet packages
- Incorrect target framework
- Transitive dependency issues from direct DLL references

Only document errors where the agent used a non-existent or incorrect Ivy Framework API.

We can also address common hallucinations by writing refactoring rules in
D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent\CSharp\IvyCSharpRefactoringService.cs

If this is applicable we should suggest refactoring rules to fix the hallucination for future sessions, and document those rules in the hallucinations.md file as well.

Don't write to the hallucinations.md directly, instead create a plan for it as described below.

## Task: Questions

If the agent asked a question and didn't get a satisfactory answer from an IvyQuestion tool call we should create add the question and answer pair to the FAQ file in D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared\Docs\05_Other\Faq.md. This will help the agent get better answers to similar questions in the future. Make sure the question isn't already in the FAQ before adding it. If it is already there, check if the existing answer is sufficient or if it needs to be improved based on the session's context.

(Note this should also be expressed as a plan file described below)

## Task: Reflect

Analyze the debugging session itself and identify any areas for improvement in the debugging process, instructions, or tools used.

How could the overall debugging experience be improved for future sessions? Are there any additional tools, resources, or instructions that could be provided to make the process smoother and more effective?

Also, if needed suggest improved logging to help with future debugging sessions throughout the code base.

(Note this should also be expressed as a plan file described below)

## Generate plans

For each finding you have from the above investigations, create a plan to address it.

Store plans in D:\Repos\_Ivy\.plans\ (the root folder, NOT in any subfolder like review\, approved\, etc.)

File name template: XXX-<RepositoryName>-Feature-<Title>.md

RepositoryName should be a short name for the repository where the fix needs to be applied (e.g. IvyAgent, IvyConsole, IvyFramework, etc.). If the finding is not specific to a single repository, use "General".

XXX should be a sequential number to ensure unique filenames and to indicate the order of plans (e.g. 001, 002, etc.).

<plan-format>
---
source: <IVY_AGENT_DEBUG_FOLDER>\<session-id>\
---
# [Title]

## Problem

## Solution

## Clean up

1. Commit

</plan-format>

The `source:` frontmatter records where the bug originated (e.g. a Langfuse session folder). Always include it when generating plans from a debug session. Use the actual resolved IVY_AGENT_DEBUG_FOLDER path and session ID.

The plan should include all paths and information for an LLM based coding agent to be able to execute the plan end-to-end without any human intervention. Keep the plan short and consise.

When generating plans - first search in the plan folder to see if there's already a plan for the same exact finding. If there is check if the existing plan is sufficient to address the finding. If it is, we can skip creating a new plan. If it's not sufficient, adjust the existing plan to cover the new finding.

EVERYTHING SHOULD BE EXPRESSED AS A PLAN, Inluding Github issue creation, edits to hallucinations.md, etc.
