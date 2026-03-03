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
