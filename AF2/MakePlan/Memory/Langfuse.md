## Debugging with Langfuse

If the task description mentions a session ID or trace ID (typically a GUID), use `ivy-agent langfuse` to fetch and analyze the session before creating plans.

### Steps

1. Get the IVY_AGENT_DEBUG_FOLDER path:

    powershell -Command '[Environment]::GetEnvironmentVariable("IVY_AGENT_DEBUG_FOLDER", "User")'

If empty, try Machine scope.

2. Fetch the session trace (if not already cached in a `langfuse` subfolder):

    ivy-agent langfuse session get <session-id>

3. Get a compact timeline overview:

    ivy-agent langfuse session timeline --session-id <session-id> -c

This also works with a trace ID instead of a session ID (the session will be resolved automatically):

    ivy-agent langfuse session timeline --trace-id <trace-id> -c

See `D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent.Console\Commands\Langfuse\SessionTimelineCommand.cs` for the full command signature.

4. Analyze the trace files in `IVY_AGENT_DEBUG_FOLDER\<session-id>\langfuse\` using jq. Key patterns:
   - Observations are JSON files: `XXX_<observation-type>_<observation-name>.json`
   - Use `jq '.input'` on EVENT files, `jq '.input.messages'` on GENERATION files
   - Check for build errors: `jq '.input.message.success' *BuildProjectResultMessage*.json`
   - Check tool calls: `jq '.input' *LocalRequest*.json`

5. Cross-reference findings with local logs in `IVY_AGENT_DEBUG_FOLDER\<session-id>\`:
   - `<session-id>-client-verbose.log` - client logs
   - `<session-id>-server-verbose.log` - server logs

Create plans for each finding (hallucinations, missing FAQ entries, logging improvements, etc.).

IMPORTANT: Use the `ivy-agent` CLI tool (should be in PATH). Do NOT use `dotnet run`.
