param(
    [Parameter(Mandatory=$true)]
    [string]$PlanPath,

    [switch]$ReadyToGo
)

$resolvedPath = Resolve-Path -Path $PlanPath -ErrorAction SilentlyContinue
if (-not $resolvedPath) {
    Write-Host "File not found: $PlanPath"
    exit 1
}
$resolvedPath = $resolvedPath.Path
$originalDir = Split-Path -Parent $resolvedPath
$fileName = Split-Path -Leaf $resolvedPath

# Copy current version to history before splitting
$historyDir = Join-Path $originalDir "history"
if (-not (Test-Path $historyDir)) {
    New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
}
$historyPath = Join-Path $historyDir $fileName
Copy-Item -Path $resolvedPath -Destination $historyPath -Force
Write-Host "Previous version saved to: $historyPath"

# Move to updating directory
$updatingDir = "D:\Repos\_Ivy\.plans\updating"
if (-not (Test-Path $updatingDir)) {
    New-Item -ItemType Directory -Path $updatingDir -Force | Out-Null
}
$updatingPath = Join-Path $updatingDir $fileName
Move-Item -Path $resolvedPath -Destination $updatingPath -Force

if (-not $ReadyToGo) {
    # Open in Notepad for user to add >> annotations to guide the split
    $notepad = Start-Process notepad.exe -ArgumentList $updatingPath -PassThru
    $notepad.WaitForExit()
}

$fileContent = Get-Content -Path $updatingPath -Raw -Encoding UTF8

if ([string]::IsNullOrWhiteSpace($fileContent)) {
    Write-Host "File was empty. Restoring original and aborting."
    Copy-Item -Path $historyPath -Destination $resolvedPath -Force
    Remove-Item -Path $updatingPath -Force
    exit 1
}

# Acquire lock and reserve a batch of 5 IDs
$plansDir = "D:\Repos\_Ivy\.plans"
$counterFile = Join-Path $plansDir ".counter"
$lockFile = "$counterFile.lock"
$maxRetries = 10
$retryDelay = 500

$reservedIds = @()

for ($i = 0; $i -lt $maxRetries; $i++) {
    try {
        $lockStream = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

        if (Test-Path $counterFile) {
            $nextId = [int](Get-Content $counterFile -Raw).Trim()
        } else {
            $nextId = 200
        }

        # Reserve 5 IDs
        for ($j = 0; $j -lt 5; $j++) {
            $reservedIds += ($nextId + $j).ToString("000")
        }
        $nextId += 5
        Set-Content -Path $counterFile -Value $nextId -NoNewline -Encoding UTF8

        $lockStream.Close()
        break
    } catch [System.IO.IOException] {
        if ($i -eq ($maxRetries - 1)) {
            Write-Host "Failed to acquire lock on counter file after $maxRetries retries. Restoring original and aborting." -ForegroundColor Red
            Copy-Item -Path $historyPath -Destination $resolvedPath -Force
            Remove-Item -Path $updatingPath -Force
            exit 1
        }
        Start-Sleep -Milliseconds $retryDelay
    }
}

$idList = $reservedIds -join ", "
Write-Host "Reserved plan IDs: $idList"

$prompt = @"
You are given an implementation plan file that contains MULTIPLE distinct issues in a single file.
Split it into separate, self-contained plan files.

CRITICAL RULES:
- Each output plan must follow this exact format:

===PLAN_START===
FILENAME: <filename>
---
<plan content>
===PLAN_END===

- Use the filename template: XXX-<RepositoryName>-Feature-<Title>.md
- Available plan numbers (use in order): $idList
- RepositoryName should be a short name for the repository (e.g. IvyAgent, IvyConsole, IvyFramework, General).
- Each plan MUST have: # [Title], ## Problem, ## Solution, ## Tests, ## Finish sections.
- Each plan must include all paths and information for an LLM coding agent to execute end-to-end.
- Keep each plan short and concise - ONE ISSUE PER FILE.
- If user >> comments exist, follow their guidance for how to split.
- Output ONLY the plan blocks. No preamble, no explanation.

---

$fileContent

---

$(Get-Content -Path "$PSScriptRoot\PlanContext.md" -Raw)
"@

Write-Host "Running Claude to split plan..."
$tempPromptFile = Join-Path $updatingDir "last-claude-prompt.txt"
Set-Content -Path $tempPromptFile -Value $prompt -Encoding UTF8

$stderrFile = Join-Path $updatingDir "last-claude-stderr.txt"
$output = & "$env:USERPROFILE\.local\bin\claude.exe" --dangerously-skip-permissions -p --output-format text < $tempPromptFile 2> $stderrFile
$exitCode = $LASTEXITCODE

# Save raw output for debugging
$debugPath = Join-Path $updatingDir "last-claude-output.txt"
Set-Content -Path $debugPath -Value $output -Encoding UTF8
Write-Host "Claude output saved to: $debugPath (length: $($output.Length) chars)"

if ($exitCode -ne 0) {
    $stderr = if (Test-Path $stderrFile) { Get-Content $stderrFile -Raw } else { "(no stderr)" }
    Write-Host "ERROR: claude.exe exited with code $exitCode" -ForegroundColor Red
    Write-Host "stderr: $stderr" -ForegroundColor Yellow
    Write-Host "stdout (first 500 chars): $($output.Substring(0, [Math]::Min(500, $output.Length)))" -ForegroundColor Yellow
    Copy-Item -Path $historyPath -Destination $resolvedPath -Force
    Remove-Item -Path $updatingPath -Force
    exit 1
}

if ($output.Length -lt 500) {
    Write-Host "ERROR: Claude output suspiciously short ($($output.Length) chars). Likely an error response:" -ForegroundColor Red
    Write-Host $output -ForegroundColor Yellow
    Copy-Item -Path $historyPath -Destination $resolvedPath -Force
    Remove-Item -Path $updatingPath -Force
    exit 1
}

# Strip ANSI escape codes that may break regex matching
$output = $output -replace '\x1b\[[0-9;]*m', ''

# Parse output for ===PLAN_START=== ... ===PLAN_END=== blocks
$planPattern = '(?s)===PLAN_START===\s*\nFILENAME:\s*(.+?)\s*\n---\s*\n(.*?)===PLAN_END==='
$matches = [regex]::Matches($output, $planPattern)

if ($matches.Count -eq 0) {
    Write-Host "ERROR: No ===PLAN_START=== markers found in Claude output. Restoring original and aborting." -ForegroundColor Red
    Write-Host "First 500 chars of output:" -ForegroundColor Yellow
    Write-Host $output.Substring(0, [Math]::Min(500, $output.Length)) -ForegroundColor Yellow
    Copy-Item -Path $historyPath -Destination $resolvedPath -Force
    Remove-Item -Path $updatingPath -Force
    exit 1
}

if ($matches.Count -lt 2) {
    Write-Host "ERROR: Only $($matches.Count) plan(s) produced. Split requires at least 2. Restoring original and aborting." -ForegroundColor Red
    Copy-Item -Path $historyPath -Destination $resolvedPath -Force
    Remove-Item -Path $updatingPath -Force
    exit 1
}

# Save each plan file to the original directory
$createdFiles = @()
foreach ($match in $matches) {
    $planFileName = $match.Groups[1].Value.Trim()
    $planContent = $match.Groups[2].Value.TrimEnd()
    $planPath = Join-Path $originalDir $planFileName
    Set-Content -Path $planPath -Value $planContent -Encoding UTF8
    $createdFiles += $planFileName
    Write-Host "Created: $planPath" -ForegroundColor Green
}

# Clean up the file from updating/
Remove-Item -Path $updatingPath -Force

Write-Host ""
Write-Host "Split complete! Created $($createdFiles.Count) plan files:" -ForegroundColor Cyan
foreach ($f in $createdFiles) {
    Write-Host "  - $f"
}
