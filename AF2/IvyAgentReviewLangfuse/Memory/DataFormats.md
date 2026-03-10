# Langfuse Data Format Patterns

## IvyDocs (Request/Response Pair)
- **Request**: `EVENT__local__IvyDocs` — `input.path` contains the doc path, `input.content` has the full text
- **Response**: `EVENT_LocalResponse` (next file) — `input.toolName = "IvyDocs"`, `input.response.success`, `input.response.contentLength`, `input.response.error`

## IvyQuestion (Request/Response Pair)
- **Request**: `EVENT__local__IvyQuestion` — `input.question` has the question text
- **Response**: `EVENT_LocalResponse` (next file) — `input.toolName = "IvyQuestion"`, `input.response.success`, `input.response.answer`, `input.response.error`

## WebFetch+AnswerAgent (Question via WebFetch)
- When WebFetch is called with a `question` parameter, the server uses AnswerAgent to answer it from the fetched content.
- **WebFetch event**: `EVENT_WebFetch` — `input.url`, `input.success`, `input.contentLength`
- **AnswerAgent SPAN**: `SPAN_AnswerAgent` — `input.question`, `input.document`, `output.answer` (if successful)
- **AnswerAgent GENERATION**: `GENERATION_AnswerAgent` — child of the SPAN, contains the LLM call
- **WebFetch response**: `EVENT_LocalResponse` — `input.toolName = "WebFetch"`, `input.response.success`, `input.response.contentLength`
- **Important**: AnswerAgent success/failure is determined by `output.answer` on the SPAN. This is NOT a ToolFeedback error. ToolFeedback only occurs for tool validation errors (e.g., missing `url` parameter).

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
