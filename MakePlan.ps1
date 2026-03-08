param(
    [string]$InitialPrompt = ""
)

# Ensure UTF-8 output encoding so multi-byte characters survive process capture
$prevOutputEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$plansDir = "D:\Repos\_Ivy\.plans"
$counterFile = Join-Path $plansDir ".counter"

if ([string]::IsNullOrWhiteSpace($InitialPrompt)) {
    $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "claude-plan-$(Get-Date -Format 'yyyyMMdd-HHmmss').md")
    Set-Content -Path $tempFile -Value "" -Encoding UTF8
    $notepad = Start-Process notepad.exe -ArgumentList $tempFile -PassThru
    $notepad.WaitForExit()
    $userInput = Get-Content -Path $tempFile -Raw -Encoding UTF8
    Remove-Item $tempFile -ErrorAction SilentlyContinue
} else {
    $userInput = $InitialPrompt
}

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

$planFileName = "$nextIdFormatted-Plan.md"

$contextContent = Get-Content -Path "$PSScriptRoot\PlanContext.md" -Raw

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

File name: $planFileName

<plan-format>
# [Title]

## Problem

## Solution

## Tests

## Finish

Commit!

</plan-format>

The plan should include all paths and information for an LLM based coding agent to be able to execute the plan end-to-end without any human intervention. Keep the plan short and concise.

CRITICAL RULES:
- Do NOT create, write, or save any files. You may read files to understand the codebase.
- Wrap your entire output in ===PLAN_START=== and ===PLAN_END=== markers.
- Output the filename on the first line after the start marker as FILENAME: <filename>
- Use the filename template: $nextIdFormatted-<RepositoryName>-Feature-<Title>.md
- RepositoryName should be a short name for the repository (e.g. IvyAgent, IvyConsole, IvyFramework, General).
- Output ONLY: ===PLAN_START===, FILENAME line, then ---, then the plan, then ===PLAN_END===. Nothing else.

===REFERENCE CONTEXT (DO NOT include this in the output - this is background information only)===

$contextContent

===END OF REFERENCE CONTEXT===
$(if ($relatedFiles.Count -gt 0) {
@"

===RELATED PLANS (read for context, DO NOT include in output)===

$($relatedFiles | ForEach-Object { "- $_" } | Out-String)
===END OF RELATED PLANS===
"@
})
"@

$promptFile = Join-Path $promptsDir "$nextIdFormatted-prompt.txt"
Set-Content -Path $promptFile -Value $prompt -Encoding UTF8
Write-Host "Prompt saved to: $promptFile" -ForegroundColor Green

Write-Host "Running Claude to create plan..."
$output = ($prompt | & "$env:USERPROFILE\.local\bin\claude.exe" --dangerously-skip-permissions -p --output-format text 2>$null) -join "`n"
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($output)) {
    Write-Host "ERROR: Claude failed (exit code $exitCode)" -ForegroundColor Red
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    exit 1
}

# Strip ANSI escape codes
$output = $output -replace '\x1b\[[0-9;]*m', ''

# Parse output for ===PLAN_START=== ... ===PLAN_END=== block
$planPattern = '(?s)===PLAN_START===\s*\nFILENAME:\s*(.+?)\s*\n---\s*\n(.*?)===PLAN_END==='
$match = [regex]::Match($output, $planPattern)

if (-not $match.Success) {
    Write-Host "ERROR: No ===PLAN_START=== markers found in Claude output. Aborting." -ForegroundColor Red
    Write-Host "First 500 chars of output:" -ForegroundColor Yellow
    Write-Host $output.Substring(0, [Math]::Min(500, $output.Length)) -ForegroundColor Yellow
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    exit 1
}

$planFileName = $match.Groups[1].Value.Trim()
$planContent = $match.Groups[2].Value.TrimEnd()

# Normalize line endings and write UTF-8 without BOM
$planContent = $planContent -replace "`r`n", "`n" -replace "`r", "`n"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$planPath = Join-Path $plansDir $planFileName
[System.IO.File]::WriteAllText($planPath, $planContent, $utf8NoBom)

Write-Host "Created: $planPath" -ForegroundColor Green
