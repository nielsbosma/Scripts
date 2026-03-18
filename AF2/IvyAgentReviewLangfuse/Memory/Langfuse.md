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

### Tool-Based Events Also Moved to Metadata

As of 2026-03-16, tool-based events (non-message format) have ALSO moved to `metadata`:
- IvyDocs request: `metadata.path`, `metadata.content` (was `input.path`, `input.content`)
- LocalResponse: `metadata.toolName`, `metadata.response` (was `input.toolName`, `input.response`)
- IvyQuestion, WebFetch, ToolFeedback: likely also in `metadata` now

All tools must check BOTH `input` and `metadata` for tool-based events, not just for message events.

**Critical pattern**: Any tool loop starting with `if (-not $input) { continue }` will skip all new-format events.
The correct approach is to check both locations before filtering.

### Example Files

Session `6e26947f-0776-4fa1-b518-f02f544c78a3` demonstrates the new format:
- All BuildProjectResultMessage events are in `metadata.message`
- All WriteFileMessage events are in `metadata.message`
- File: `001_AgentOrchestrator/086_EVENT__in__BuildProjectResultMessage.json`

## Embedded Observations Format

As of 2026-03-18, some sessions have all observations embedded in `trace.json` under the `observations` array, with NO separate observation JSON files in the trace folder.

The PowerShell tools expect separate `{NNN}_{TYPE}_{NAME}.json` files. When only `trace.json` exists, observations must be extracted first:

```powershell
$trace = Get-Content "$traceDir/trace.json" -Raw | ConvertFrom-Json
$i = 1
foreach ($obs in $trace.observations) {
    $type = $obs.type.Substring(0, [Math]::Min(4, $obs.type.Length))
    $name = ($obs.name -replace "[^a-zA-Z0-9_]","_").Substring(0, [Math]::Min(40, $obs.name.Length))
    $filename = "{0:D3}_{1}_{2}.json" -f $i, $type, $name
    $obs | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $traceDir $filename)
    $i++
}
```

**Detection**: Check if the trace folder only contains `trace.json` and no other `.json` files. If so, extract before running tools.
