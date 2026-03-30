param(
    [switch]$Annotate,
    [switch]$Feedback,
    [switch]$Force
)

. "$PSScriptRoot\.shared\Utils.ps1"

$programFolder = GetProgramFolder $PSCommandPath
$workDir = (Get-Location).Path

# --- Test Run detection: look for test.yaml in parent folder ---
$testManagerExe = "D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent.Test.Manager\bin\Debug\net10.0\tm.exe"
$testYamlPath = Join-Path (Split-Path $workDir -Parent) "test.yaml"
$testRunId = $null
$taskDescription = ""
if (Test-Path $testYamlPath) {
    $parentName = Split-Path (Split-Path $workDir -Parent) -Leaf
    if ($parentName -match "^(\d+)-(.+)$") {
        $testRunId = $Matches[1]
        $taskDescription = $Matches[2] -replace '-', ' '
        Write-Host "Detected test run ID: $testRunId, task: $taskDescription" -ForegroundColor Cyan
        & $testManagerExe run set-state $testRunId Debugging
    }
}

$sessionId = GetLatestSessionId
$args = CollectArgs $args -Optional

# --- Annotate: open client TUI log for user annotations ---
$annotationContent = ""
if ($Annotate) {
    $logPath = Join-Path $workDir ".ivy" "sessions" $sessionId "$sessionId-client-output.log"
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

# --- Feedback: open empty Notepad for free-form feedback ---
$feedbackContent = ""
if ($Feedback) {
    $tempFeedbackFile = [System.IO.Path]::GetTempFileName() + ".txt"
    Set-Content -Path $tempFeedbackFile -Value ""

    Write-Host "Opening Notepad for feedback — write your feedback, save, and close..." -ForegroundColor Cyan
    $process = Start-Process notepad $tempFeedbackFile -PassThru
    $process.WaitForExit()

    $feedbackContent = (Get-Content -Path $tempFeedbackFile -Raw).Trim()
    Remove-Item -Path $tempFeedbackFile -Force

    if ([string]::IsNullOrWhiteSpace($feedbackContent)) {
        Write-Host "No feedback provided. Aborting." -ForegroundColor Red
        exit 0
    }
}

# --- Phase 1: Run ReviewBuild (must complete first) ---
Write-Host "=== Phase 1: ReviewBuild ===" -ForegroundColor Cyan
$buildReportExists = (-not $Force) -and (Test-Path (Join-Path $workDir ".ivy\review-build.md"))
if ($buildReportExists) {
    Write-Host "Skipping ReviewBuild — review-build.md already exists" -ForegroundColor DarkGray
} else {
    $reviewBuildScript = Join-Path $PSScriptRoot "IvyAgentReviewBuild.ps1"
    & pwsh -ExecutionPolicy Bypass -File $reviewBuildScript
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: ReviewBuild exited with code $LASTEXITCODE" -ForegroundColor Yellow
    }
}

# --- Phase 2a: Run ReviewLangfuse + ReviewSpec in parallel ---
Write-Host ""
Write-Host "=== Phase 2a: ReviewLangfuse + ReviewSpec (parallel) ===" -ForegroundColor Cyan

$reviewLangfuseScript = Join-Path $PSScriptRoot "IvyAgentReviewLangfuse.ps1"
$reviewSpecScript = Join-Path $PSScriptRoot "IvyAgentReviewSpec.ps1"
$reviewTestsScript = Join-Path $PSScriptRoot "IvyAgentReviewTests.ps1"

$jobs = @()
$jobs += Start-Job -Name "ReviewLangfuse" -ScriptBlock {
    Set-Location $using:workDir
    $ivyDir = Join-Path $using:workDir ".ivy"
    $langfuseFiles = @(
        "langfuse-timeline.md", "langfuse-hallucinations.md", "langfuse-questions.md",
        "langfuse-workflows.md", "langfuse-reference-connections.md", "langfuse-docs.md",
        "langfuse-build-errors.md", "langfuse-session-status.md"
    )
    $allExist = (-not $using:Force) -and ($langfuseFiles | ForEach-Object { Test-Path (Join-Path $ivyDir $_) }) -notcontains $false
    if ($allExist) {
        Write-Host "Skipping ReviewLangfuse — reports already exist" -ForegroundColor DarkGray
        return
    }
    & pwsh -ExecutionPolicy Bypass -File $using:reviewLangfuseScript
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: ReviewLangfuse exited with code $LASTEXITCODE" -ForegroundColor Yellow
    }
}
$jobs += Start-Job -Name "ReviewSpec" -ScriptBlock {
    Set-Location $using:workDir
    $ivyDir = Join-Path $using:workDir ".ivy"
    $specExists = (-not $using:Force) -and (Test-Path (Join-Path $ivyDir "review-spec.md"))
    if ($specExists) {
        Write-Host "Skipping ReviewSpec — review-spec.md already exists" -ForegroundColor DarkGray
        return
    }
    & pwsh -ExecutionPolicy Bypass -File $using:reviewSpecScript
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

# --- Phase 2b: Run ReviewTests (conditional on spec review) ---
Write-Host ""
Write-Host "=== Phase 2b: ReviewTests (conditional on spec review) ===" -ForegroundColor Cyan

$ivyDir = Join-Path $workDir ".ivy"
$specReviewPath = Join-Path $ivyDir "review-spec.md"
$skipTests = $false

if (Test-Path $specReviewPath) {
    $specContent = Get-Content $specReviewPath -Raw
    $impl = 0; $partial = 0; $missing = 0
    if ($specContent -match '\|\s*Implemented\s*\|\s*(\d+)\s*\|') { $impl = [int]$Matches[1] }
    if ($specContent -match '\|\s*Partial\s*\|\s*(\d+)\s*\|') { $partial = [int]$Matches[1] }
    if ($specContent -match '\|\s*Missing\s*\|\s*(\d+)\s*\|') { $missing = [int]$Matches[1] }
    $total = $impl + $partial + $missing
    $implPercent = if ($total -gt 0) { [math]::Round(($impl + $partial) / $total * 100) } else { 0 }

    if ($implPercent -lt 30) {
        $skipTests = $true
        Write-Host "Skipping ReviewTests — implementation is $implPercent% ($impl implemented, $partial partial, $missing missing; threshold: 30%)" -ForegroundColor Yellow

        $projectName = Split-Path $workDir -Leaf

        $stubTests = @"
# Test Review: $projectName

## Result

⏭️ **SKIPPED** - Implementation below test threshold

## Reason

Spec review shows $implPercent% implementation ($impl implemented, $partial partial, $missing missing).
Tests require at least 30% implementation to be meaningful.
"@
        $stubUx = @"
# UX Review: $projectName

## Result

⏭️ **SKIPPED** - Implementation below test threshold

## Reason

Spec review shows $implPercent% implementation. UX review requires testable apps.
"@
        if (-not (Test-Path $ivyDir)) { New-Item -ItemType Directory -Path $ivyDir | Out-Null }
        $stubTests | Set-Content (Join-Path $ivyDir "review-tests.md")
        $stubUx | Set-Content (Join-Path $ivyDir "review-ux.md")
    }
}

if (-not $skipTests) {
    $testsExist = (-not $Force) -and (Test-Path (Join-Path $ivyDir "review-tests.md")) -and (Test-Path (Join-Path $ivyDir "review-ux.md"))
    if ($testsExist) {
        Write-Host "Skipping ReviewTests — reports already exist" -ForegroundColor DarkGray
    } else {
        & pwsh -ExecutionPolicy Bypass -File $reviewTestsScript
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Warning: ReviewTests exited with code $LASTEXITCODE" -ForegroundColor Yellow
        }
    }
}

# --- Generate summary.yaml from langfuse data ---
$langfuseDir = Join-Path $workDir ".ivy" "sessions" $sessionId "langfuse"
if (Test-Path $langfuseDir) {
    Write-Host "Generating summary.yaml..." -ForegroundColor Cyan

    $sessionStatusScript = Join-Path $PSScriptRoot "IvyAgentReviewLangfuse\Tools\Get-SessionStatus.ps1"
    $sessionStatus = & $sessionStatusScript -LangfuseDir $langfuseDir
    Write-Host "Session status: $($sessionStatus.Status) — $($sessionStatus.StopReason)" -ForegroundColor $(
        if ($sessionStatus.Status -eq 'Complete') { 'Green' }
        elseif ($sessionStatus.Status -eq 'Failed') { 'Red' }
        else { 'Yellow' }
    )

    $summaryScript = Join-Path $PSScriptRoot "IvyAgentReviewLangfuse\Tools\Get-SessionSummary.ps1"
    $summaryArgs = @{ LangfuseDir = $langfuseDir; IvyDir = (Join-Path $workDir ".ivy") }
    if ($taskDescription) { $summaryArgs.TaskDescription = $taskDescription }
    $summary = & $summaryScript @summaryArgs

    $ivyDir = Join-Path $workDir ".ivy"
    if (-not (Test-Path $ivyDir)) { New-Item -ItemType Directory -Path $ivyDir | Out-Null }

    $specReview = Join-Path $ivyDir "review-spec.md"
    $specImpl = 0; $specPartial = 0; $specMissing = 0
    if (Test-Path $specReview) {
        $specContent = Get-Content $specReview -Raw
        if ($specContent -match '\|\s*Implemented\s*\|\s*(\d+)\s*\|') { $specImpl = [int]$Matches[1] }
        if ($specContent -match '\|\s*Partial\s*\|\s*(\d+)\s*\|') { $specPartial = [int]$Matches[1] }
        if ($specContent -match '\|\s*Missing\s*\|\s*(\d+)\s*\|') { $specMissing = [int]$Matches[1] }
    }

    $yamlLines = @(
        "# Auto-generated by IvyAgentDebug.ps1"
        "sessionStatus: $($sessionStatus.Status)"
        "stopReason: `"$($sessionStatus.StopReason)`""
        "generationCount: $($summary.GenerationCount)"
        "totalInputTokens: $($summary.TotalInputTokens)"
        "totalOutputTokens: $($summary.TotalOutputTokens)"
        "ivyQuestionCount: $($summary.IvyQuestionCount)"
        "ivyQuestionFailCount: $($summary.IvyQuestionFailCount)"
        "ivyDocsCount: $($summary.IvyDocsCount)"
        "ivyDocsFailCount: $($summary.IvyDocsFailCount)"
        "buildAttempts: $($summary.BuildAttempts)"
        "buildFailures: $($summary.BuildFailures)"
        "writeFileCount: $($summary.WriteFileCount)"
        "uniqueFilesWritten: $($summary.UniqueFilesWritten)"
        "bashCount: $($summary.BashCount)"
        "bashFailures: $($summary.BashFailures)"
        "readFileCount: $($summary.ReadFileCount)"
        "grepCount: $($summary.GrepCount)"
        "globCount: $($summary.GlobCount)"
        "webFetchCount: $($summary.WebFetchCount)"
        "webSearchCount: $($summary.WebSearchCount)"
        "lspCount: $($summary.LspCount)"
        "toolFeedbackCount: $($summary.ToolFeedbackCount)"
        "totalCost: $($summary.TotalCost)"
        "oneShotScore: $($summary.OneShotScore)"
        "hasGenerationFailure: $($summary.HasGenerationFailure)"
        "specImplemented: $($summary.SpecImplemented)"
        "specPartial: $($summary.SpecPartial)"
        "specMissing: $($summary.SpecMissing)"
        "workflows: [$($summary.WorkflowNames -join ', ')]"
        "specImplemented: $specImpl"
        "specPartial: $specPartial"
        "specMissing: $specMissing"
    )
    $yamlLines | Set-Content (Join-Path $ivyDir "summary.yaml")
    Write-Host "summary.yaml written." -ForegroundColor Green
}

# --- Phase 3: Agentic analysis → dump to Tendril Inbox ---
Write-Host ""
Write-Host "=== Phase 3: Analysis ===" -ForegroundColor Cyan

if ($args -eq "(No Args)") {
    $args = $sessionId
} else {
    $args = "$sessionId $args"
}

# Write annotations to .ivy/ so the agent can read them
if ($annotationContent -ne "") {
    $annotationFile = Join-Path $workDir ".ivy\annotated.md"
    Set-Content -Path $annotationFile -Value $annotationContent
    Write-Host "Annotations saved to: $annotationFile"
}

# Write feedback to .ivy/ so the agent can read them
if ($feedbackContent -ne "") {
    $feedbackFile = Join-Path $workDir ".ivy\feedback.md"
    Set-Content -Path $feedbackFile -Value $feedbackContent
    Write-Host "Feedback saved to: $feedbackFile"
}

$logFile = GetNextLogFile $programFolder
$args | Set-Content $logFile
Write-Host "Log file: $logFile"

$promptFile = PrepareFirmware $PSScriptRoot $logFile $programFolder @{ Args = $args; WorkDir = $workDir; SessionId = $sessionId }

Write-Host "Starting Agent..."
Push-Location $programFolder
claude --dangerously-skip-permissions -p -- (Get-Content $promptFile -Raw)
Pop-Location

Remove-Item $promptFile

# --- Set Ready if in a test run context ---
if ($testRunId) {
    & $testManagerExe run set-state $testRunId Ready
}
