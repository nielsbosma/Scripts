# Langfuse Analysis Reference

## Session Folder Structure

```
IVY_AGENT_DEBUG_FOLDER\<session-id>\
  <session-id>-client-verbose.log      <- root client ILogger output
  <session-id>-client-output.log       <- root interactive TUI output (only with --log-output)
  <session-id>-server-verbose.log      <- root server logs
  <task-trace-id>-client-verbose.log   <- per sub-task client logs
  <task-trace-id>-server-verbose.log   <- per sub-task server logs
```

The root connection uses session-id as its trace ID. Each sub-task gets a unique trace ID (`TaskMessage.TraceId`).

## Langfuse File Structure

```
langfuse\XXX_<trace-name>\XXX_<observation-type>_<observation-name>.json
langfuse\XXX_<trace-name>\trace.json
```

Observation filenames have bracket characters normalized to underscores (e.g., `LocalRequest_in_` instead of `LocalRequest[in]`).

## Timeline Command

```
ivy-agent langfuse session timeline --session-id <session-id> -c
ivy-agent langfuse session timeline --trace-id <trace-id> -c
```

Flags:
- `--compact` / `-c`: Omit UI noise events. Always use by default.
- `--filter` / `-f`: Comma-separated name filters (e.g. `IvyDocs,IvyQuestion`)
- `--build-errors`: Show only build error progression

## JSON Path Cheat Sheet

```
$.type                          -> "EVENT" or "GENERATION"
$.name                          -> observation name
$.traceId                       -> trace correlation ID
$.input.content                 -> (EVENT) document/data content
$.input.messages[*].role        -> (GENERATION) message roles
$.input.messages[0].contents[0].text  -> (GENERATION) system prompt
$.input.tools[*].function.name  -> (GENERATION) available tool names
$.output                        -> model response text
$.metadata.finishReason         -> stop reason
$.model                         -> model name
$.latency                       -> seconds elapsed
$.level                         -> DEFAULT / WARNING / ERROR
$.statusMessage                 -> error details
```

### BuildProjectResultMessage

```
$.input.message.success              -> build success boolean
$.input.message.buildResults[].relativePath    -> source file path
$.input.message.buildResults[].buildErrors[].message  -> error message
$.input.message.buildResults[].buildErrors[].line     -> line number
$.input.message.buildResults[].buildErrors[].errorCode -> CS error code
```

## Debugging Recipes

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

**Show all tool feedback errors:**
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

**Show file writes:**
```
jq 'select(.name | test("WriteFileMessage")) | .input.message.filepath' *.json
```

**Show user's initial prompt:**
```
jq -r '.input.messages[1].contents[0].text // .input.messages[1].content' 002_GENERATION_PersonaAgent.json
```

**Extract all build errors:**
```bash
for f in *BuildProjectResultMessage*.json; do echo "=== $f ===" && jq '[.input.message.buildResults[]?.buildErrors[]? | {message, line}]' "$f"; done
```

**Show IvyQuestion Q&A pairs:**
```bash
for f in *IvyQuestion*.json; do echo "=== $f ===" && jq '{question: .input.question, answer: .input.answer[0:300]}' "$f"; done
```

**Find hallucinations — builds with errors:**
```bash
for f in *BuildProjectResultMessage*.json; do jq -r 'select(.input.message.success == false) | "=== \(.name // input_filename) ===\n" + ([.input.message.buildResults[]?.buildErrors[]? | "\(.relativePath):\(.line) \(.errorCode): \(.message)"] | join("\n"))' "$f"; done
```

**Show file writes before failed builds:**
```bash
jq -s '[.[] | {name, type: (if .name | test("WriteFile") then "WRITE" elif .name | test("BuildProject") then "BUILD" else null end), file: .input.message.filepath?, success: .input.message.success?}] | [.[] | select(.type != null)]' *.json
```

## Workflow Debugging

Workflow source files: `D:\Repos\_Ivy\Ivy\Ivy.Internals\Workflows\<Category>\<WorkflowName>\`
Each has a `.cs` file and a `Prompts\` subfolder with markdown templates.

## LSP Coordinate Systems

`LspMessage` stores 0-based coordinates internally (LSP protocol). Add 1 to match editor line numbers. Build errors and grep results use 1-based in LLM-facing output.

## Tool Call Debugging

1. Check `EVENT_LocalRequest` — processed tool arguments for local tools (WebSearch, WebFetch, IvyDocs, IvyQuestion)
2. Check tool schema in GENERATION files: `jq '.input.tools[] | select(.function.name == "ToolName") | .function.parameters'`
3. Cross-reference `EVENT_LocalResponse` for what the tool returned
