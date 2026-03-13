# Langfuse Data Format

## Message Location Change

As of 2026-03-13, Langfuse observation JSON structure changed where message data is stored:

**Old format** (prior to 2026-03-13):
```json
{
  "input": {
    "message": {
      "$type": "BuildProjectResultMessage",
      "success": true,
      ...
    }
  },
  "metadata": {}
}
```

**New format** (2026-03-13 onwards):
```json
{
  "input": null,
  "output": null,
  "metadata": {
    "message": {
      "$type": "BuildProjectResultMessage",
      "success": true,
      ...
    }
  }
}
```

### Impact

All message-based events moved from `input.message` to `metadata.message`:
- BuildProjectResultMessage
- WriteFileMessage / WriteFileResultMessage
- ReadFileMessage
- BashMessage / BashResultMessage
- GrepMessage / GlobMessage
- WorkflowStartMessage / WorkflowFinishedMessage / WorkflowFailedMessage
- WorkflowTransitionMessage / WorkflowStateMessage
- WorkflowReferenceMessage / WorkflowReferenceResultMessage
- GetTypeInfoMessage / GetTypeInfoResultMessage
- ToolFeedback

### Backwards Compatibility

All PowerShell tools in `Tools/` now check both locations:

```powershell
# Check both input.message (old format) and metadata.message (new format)
$message = $null
if ($json.input -and $json.input.message) {
    $message = $json.input.message
} elseif ($json.metadata -and $json.metadata.message) {
    $message = $json.metadata.message
}

if (-not $message -or -not $message.'$type') { continue }
```

### Tool-Based Events Still in Input

Tool-based events (non-message format) remain in `input`:
- IvyQuestion: `input.toolName`, `input.request`, `input.response`
- IvyDocs: `input.toolName`, `input.request`, `input.response`
- WebFetch: `input.toolName`, `input.request`, `input.response`
- ToolFeedback (direct format): `input.toolName`, `input.feedback`

### Example Files

Session `6e26947f-0776-4fa1-b518-f02f544c78a3` demonstrates the new format:
- All BuildProjectResultMessage events are in `metadata.message`
- All WriteFileMessage events are in `metadata.message`
- File: `001_AgentOrchestrator/086_EVENT__in__BuildProjectResultMessage.json`
