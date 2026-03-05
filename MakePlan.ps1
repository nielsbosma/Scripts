$tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "claude-plan-$(Get-Date -Format 'yyyyMMdd-HHmmss').md")

$template = @"
Make an implementation plan for the following task:

----



----

We are working in the following directories.

D:\Repos\_Ivy\Ivy-Agent\
D:\Repos\_Ivy\Ivy\
D:\Repos\_Ivy\Ivy-Framework\
D:\Repos\_Ivy\Ivy-Mcp\

Store plans in D:\Repos\_Ivy\.plans\

File name template: XXX-<RepositoryName>-Feature-<Title>.md

RepositoryName should be a short name for the repository where the fix needs to be applied (e.g. IvyAgent, IvyConsole, IvyFramework, etc.). If the finding is not specific to a single repository, use "General".

XXX should be a sequential number to ensure unique filenames and to indicate the order of plans (e.g. 001, 002, etc.).

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


"@

Set-Content -Path $tempFile -Value $template -Encoding UTF8

$notepad = Start-Process notepad.exe -ArgumentList $tempFile -PassThru
$notepad.WaitForExit()

$prompt = Get-Content -Path $tempFile -Raw -Encoding UTF8

if ([string]::IsNullOrWhiteSpace($prompt)) {
    Write-Host "File was empty. Aborting."
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "Running Claude with plan prompt..."
claude --dangerously-skip-permissions -p $prompt

Remove-Item $tempFile -ErrorAction SilentlyContinue
