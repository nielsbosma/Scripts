param(
    [switch]$Annotate
)

. "$PSScriptRoot\.shared\Utils.ps1"

$programFolder = GetProgramFolder $PSCommandPath
$workDir = (Get-Location).Path

$sessionId = GetLatestSessionId
$args = CollectArgs $args -Optional

# --- Annotate: open client TUI log for user annotations ---
$annotationContent = ""
if ($Annotate) {
    $debugFolder = if ($env:IVY_AGENT_DEBUG_FOLDER) { $env:IVY_AGENT_DEBUG_FOLDER.Trim() } else { $null }
    if (-not $debugFolder) {
        Write-Host "Error: IVY_AGENT_DEBUG_FOLDER environment variable is not set." -ForegroundColor Red
        exit 1
    }

    $logPath = Join-Path (Join-Path $debugFolder $sessionId) "$sessionId-client-output.log"
    if (-not (Test-Path $logPath)) {
        Write-Host "Client output log not found: $logPath" -ForegroundColor Red
        exit 1
    }

    $logContent = Get-Content -Path $logPath -Raw
    $tempAnnotateFile = [System.IO.Path]::GetTempFileName() + ".txt"
    Set-Content -Path $tempAnnotateFile -Value @"
Annotate with ">>" prefix on lines you want the agent to investigate.

---
$logContent
---
"@

    Write-Host "Opening client output for annotation..." -ForegroundColor Cyan
    $process = Start-Process notepad $tempAnnotateFile -PassThru
    $process.WaitForExit()

    $annotationContent = (Get-Content -Path $tempAnnotateFile -Raw).Trim()
    Remove-Item -Path $tempAnnotateFile -Force

    if ([string]::IsNullOrWhiteSpace($annotationContent)) {
        Write-Host "No annotations provided. Continuing without." -ForegroundColor Yellow
        $annotationContent = ""
    }
}

# --- Phase 1: Run ReviewBuild (must complete first) ---
Write-Host "=== Phase 1: ReviewBuild ===" -ForegroundColor Cyan
$reviewBuildScript = Join-Path $PSScriptRoot "IvyAgentReviewBuild.ps1"
& pwsh -ExecutionPolicy Bypass -File $reviewBuildScript
if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: ReviewBuild exited with code $LASTEXITCODE" -ForegroundColor Yellow
}

# --- Phase 2: Run ReviewLangfuse, ReviewSpec, ReviewTests in parallel ---
Write-Host ""
Write-Host "=== Phase 2: ReviewLangfuse + ReviewSpec + ReviewTests (parallel) ===" -ForegroundColor Cyan

$reviewLangfuseScript = Join-Path $PSScriptRoot "IvyAgentReviewLangfuse.ps1"
$reviewSpecScript = Join-Path $PSScriptRoot "IvyAgentReviewSpec.ps1"
$reviewTestsScript = Join-Path $PSScriptRoot "IvyAgentReviewTests.ps1"

$jobs = @()
$jobs += Start-Job -Name "ReviewLangfuse" -ScriptBlock {
    Set-Location $using:workDir
    & pwsh -ExecutionPolicy Bypass -File $using:reviewLangfuseScript
}
$jobs += Start-Job -Name "ReviewSpec" -ScriptBlock {
    Set-Location $using:workDir
    & pwsh -ExecutionPolicy Bypass -File $using:reviewSpecScript
}
$jobs += Start-Job -Name "ReviewTests" -ScriptBlock {
    Set-Location $using:workDir
    & pwsh -ExecutionPolicy Bypass -File $using:reviewTestsScript
}

Write-Host "Waiting for parallel jobs: $($jobs.Name -join ', ')..."
$jobs | ForEach-Object {
    $job = $_ | Wait-Job
    $output = $job | Receive-Job
    Write-Host ""
    Write-Host "--- $($job.Name) (State: $($job.State)) ---" -ForegroundColor $(if ($job.State -eq 'Completed') { 'Green' } else { 'Yellow' })
    $output | ForEach-Object { Write-Host $_ }
}
$jobs | Remove-Job -Force

# --- Phase 3: Agentic analysis ---
Write-Host ""
Write-Host "=== Phase 3: Analysis ===" -ForegroundColor Cyan

if ($args -eq "(No Args)") {
    $args = $sessionId
} else {
    $args = "$sessionId $args"
}

# Write annotations to .ivy/ so the agent can read them
if ($annotationContent -ne "") {
    $annotationFile = Join-Path $workDir ".ivy\annotations.md"
    Set-Content -Path $annotationFile -Value $annotationContent
    Write-Host "Annotations saved to: $annotationFile"
}

$logFile = GetNextLogFile $programFolder
$args | Set-Content $logFile
Write-Host "Log file: $logFile"

$promptFile = PrepareFirmware $PSScriptRoot $logFile @{ Args = $args; WorkDir = $workDir; SessionId = $sessionId }

Write-Host "Starting Claude Code..."
Push-Location $programFolder
claude --dangerously-skip-permissions -p -- (Get-Content $promptFile -Raw)
Pop-Location

Remove-Item $promptFile
