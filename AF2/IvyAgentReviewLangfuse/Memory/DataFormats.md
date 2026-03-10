# Langfuse Data Format Patterns

## IvyDocs (Request/Response Pair)
- **Request**: `EVENT__local__IvyDocs` — `input.path` contains the doc path, `input.content` has the full text
- **Response**: `EVENT_LocalResponse` (next file) — `input.toolName = "IvyDocs"`, `input.response.success`, `input.response.contentLength`, `input.response.error`

## IvyQuestion (Request/Response Pair)
- **Request**: `EVENT__local__IvyQuestion` — `input.question` has the question text
- **Response**: `EVENT_LocalResponse` (next file) — `input.toolName = "IvyQuestion"`, `input.response.success`, `input.response.answer`, `input.response.error`
- **AnswerAgent variant**: Sometimes questions go through `SPAN_AnswerAgent` → `GENERATION_AnswerAgent` instead. The SPAN has `input.question` and `input.document`. The generation output is the answer text.

## Workflows
- `EVENT__out__WorkflowStartMessage` — `input.message.WorkflowName` (note: the tool reads WorkflowName from different fields)
- `EVENT__in__WorkflowTransitionMessage` — transition events
- `EVENT__out__WorkflowStateMessage` — `input.message.StateName` (note: WorkflowName may be empty here)
- `EVENT__in__WorkflowFinishedMessage` — `input.message.success`

## Build Results
- `EVENT__in__BuildProjectResultMessage` — build success/failure and error details

## File Writes
- `EVENT__out__WriteFileMessage` — `input.message.path` has the file path

## Tool Pairing Pattern
Most local tools follow: `EVENT__local__{ToolName}` (request) → `EVENT_LocalResponse` (response with `input.toolName`)
