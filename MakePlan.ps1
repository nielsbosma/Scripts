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

& code --wait $tempFile

$userInput = Get-Content -Path $tempFile -Raw -Encoding UTF8

$relatedFiles = @()
$firstLine = ($userInput.Trim() -split "`n")[0]
$groupNumbers = [regex]::Matches($firstLine, '\[(\d+)\]') | ForEach-Object { $_.Groups[1].Value }
if ($groupNumbers.Count -gt 0) {
    $allPlanFiles = Get-ChildItem -Path $plansDir -Recurse -File
    foreach ($groupNumber in $groupNumbers) {
        $relatedFiles += $allPlanFiles | Where-Object { $_.Name -match "^$groupNumber-" } | Select-Object -ExpandProperty FullName
    }
}

if ([string]::IsNullOrWhiteSpace($userInput)) {
    Write-Host "File was empty. Aborting."
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    exit 1
}

Write-Host ""
Write-Host "--- Your prompt ---" -ForegroundColor Cyan
Write-Host $userInput.Trim()
Write-Host "-------------------" -ForegroundColor Cyan
Write-Host ""

$lockFile = "$counterFile.lock"
$maxRetries = 10
$retryDelay = 500  # milliseconds

for ($i = 0; $i -lt $maxRetries; $i++) {
    try {
        # Open lock file with exclusive access - this is the mutex
        $lockStream = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

        # Read counter while holding lock
        if (Test-Path $counterFile) {
            $nextId = [int](Get-Content $counterFile -Raw).Trim()
        } else {
            $nextId = 200
        }
        $nextIdFormatted = $nextId.ToString("000")
        $nextId++
        Set-Content -Path $counterFile -Value $nextId -NoNewline -Encoding UTF8

        # Release lock
        $lockStream.Close()
        break
    } catch [System.IO.IOException] {
        if ($i -eq ($maxRetries - 1)) {
            Write-Host "Failed to acquire lock on counter file after $maxRetries retries. Aborting." -ForegroundColor Red
            exit 1
        }
        Start-Sleep -Milliseconds $retryDelay
    }
}

$promptsDir = Join-Path $plansDir "prompts"
if (-not (Test-Path $promptsDir)) {
    New-Item -ItemType Directory -Path $promptsDir | Out-Null
}

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

$(Get-Content -Path "$PSScriptRoot\PlanContext.md" -Raw)
$(if ($relatedFiles.Count -gt 0) {
@"

## Related plans

The following existing plan files are related to this task. Read them for context:

$($relatedFiles | ForEach-Object { "- $_" } | Out-String)
"@
})
"@

$promptFile = Join-Path $promptsDir "$nextIdFormatted-prompt.txt"
Set-Content -Path $promptFile -Value $prompt -Encoding UTF8
Write-Host "Prompt saved to: $promptFile" -ForegroundColor Green

Write-Host "Running Claude with plan prompt..."
& "$env:USERPROFILE\.local\bin\claude.exe" -p --dangerously-skip-permissions $prompt

Remove-Item $tempFile -ErrorAction SilentlyContinue
