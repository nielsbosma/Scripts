# Re-launch in Windows Terminal if running in legacy conhost
if (-not $env:WT_SESSION) {
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process wt -ArgumentList "powershell -ExecutionPolicy Bypass -NoExit -File `"$scriptPath`""
    exit 0
}

$plansDir = "D:\Repos\_Ivy\.plans"
$counterFile = Join-Path $plansDir ".counter"

$tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "claude-plan-$(Get-Date -Format 'yyyyMMdd-HHmmss').md")
Set-Content -Path $tempFile -Value "" -Encoding UTF8

$notepad = Start-Process notepad.exe -ArgumentList $tempFile -PassThru
$notepad.WaitForExit()

$userInput = Get-Content -Path $tempFile -Raw -Encoding UTF8

if ([string]::IsNullOrWhiteSpace($userInput)) {
    Write-Host "File was empty. Aborting."
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    exit 1
}

if (Test-Path $counterFile) {
    $nextId = [int](Get-Content $counterFile -Raw).Trim()
} else {
    $nextId = 200
}
$nextIdFormatted = $nextId.ToString("000")
$nextId++
Set-Content -Path $counterFile -Value $nextId -NoNewline -Encoding UTF8

$prompt = @"
Make an implementation plan for the following task:

----

$($userInput.Trim())

----

We are working in the following directories.

D:\Repos\_Ivy\Ivy-Agent\
D:\Repos\_Ivy\Ivy\
D:\Repos\_Ivy\Ivy-Framework\
D:\Repos\_Ivy\Ivy-Mcp\

Store plans in D:\Repos\_Ivy\.plans\

File name template: XXX-<RepositoryName>-Feature-<Title>.md

RepositoryName should be a short name for the repository where the fix needs to be applied (e.g. IvyAgent, IvyConsole, IvyFramework, etc.). If the finding is not specific to a single repository, use "General".

The next plan number is $nextIdFormatted. Use this exact number. Do not scan existing files for the next number.

<plan-format>
# [Title]

## Problem

## Solution

## Tests

## Finish

Commit!

</plan-format>

The plan should include all paths and information for an LLM based coding agent to be able to execute the plan end-to-end without any human intervention. Keep the plan short and consise.

## Folders and important files

[Client]
D:\Repos\_Ivy\Ivy\Ivy.Console\
D:\Repos\_Ivy\Ivy\Ivy.Internals\

[Server]
D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent.Server
D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent

[Shared]
D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent.Shared
(Shared code between client and server, including message definitions and agent personas.)

[Tools]
D:\Repos\_Ivy\Ivy-Inspectors

[MCP]
D:\Repos\_Ivy\Ivy-Mcp
(This is the service that we call for IvyQuestions and IvyDocs.)

The client and server communicates over websockets and sends "messages". All messages in the system are
defined in:

D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent.Shared\Messages

Workflow definitions are defined in:
D:\Repos\_Ivy\Ivy\Ivy.Internals\Workflows

Read more about how workflows are created in:
D:\Repos\_Ivy\Ivy\Ivy.Internals\Workflows\Internal\Workflows\CreateOrEditWorkflowWorkflow.workflow

Prompt for the Developer persona (default):
D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent\Agents\Personas\Prompts\Developer.md

AGENTS.MD (basic Ivy instructions):
D:\Repos\_Ivy\Ivy-Framework\AGENTS.md

Reference connections:
D:\Repos\_Ivy\Ivy\connections

Docs:
D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared\Docs

Samples:
D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Samples\

Breaking changes are documented as "refactor" prompts:
D:\Repos\_Ivy\Ivy-Framework\src\.releases\Refactors

## Debugging with Langfuse

If the task description above mentions a session ID or trace ID (typically a GUID), use ``ivy-agent langfuse`` to fetch and analyze the session before creating plans.

### Steps

1. Get the IVY_AGENT_DEBUG_FOLDER path:

    powershell -Command '[Environment]::GetEnvironmentVariable("IVY_AGENT_DEBUG_FOLDER", "User")'

If empty, try Machine scope.

2. Fetch the session trace (if not already cached in a ``langfuse`` subfolder):

    ivy-agent langfuse session get <session-id>

3. Get a compact timeline overview:

    ivy-agent langfuse session timeline --session-id <session-id> -c

This also works with a trace ID instead of a session ID (the session will be resolved automatically):

    ivy-agent langfuse session timeline --trace-id <trace-id> -c

See ``D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent.Console\Commands\Langfuse\SessionTimelineCommand.cs`` for the full command signature.

4. Analyze the trace files in ``IVY_AGENT_DEBUG_FOLDER\<session-id>\langfuse\`` using jq. Key patterns:
   - Observations are JSON files: ``XXX_<observation-type>_<observation-name>.json``
   - Use ``jq '.input'`` on EVENT files, ``jq '.input.messages'`` on GENERATION files
   - Check for build errors: ``jq '.input.message.success' *BuildProjectResultMessage*.json``
   - Check tool calls: ``jq '.input' *LocalRequest*.json``

5. Cross-reference findings with local logs in ``IVY_AGENT_DEBUG_FOLDER\<session-id>\``:
   - ``<session-id>-client-verbose.log`` - client logs
   - ``<session-id>-server-verbose.log`` - server logs

6. For full debugging reference, see: ``D:\Repos\_Ivy\Ivy-Agent\.claude\commands\debug-agent-session.md``

Create plans for each finding (hallucinations, missing FAQ entries, logging improvements, etc.).

IMPORTANT: Use the ``ivy-agent`` CLI tool (should be in PATH). Do NOT use ``dotnet run``.
"@

Write-Host "Running Claude with plan prompt..."
& "$env:USERPROFILE\.local\bin\claude.exe" -p --dangerously-skip-permissions $prompt

Remove-Item $tempFile -ErrorAction SilentlyContinue
