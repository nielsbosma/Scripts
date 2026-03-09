param(
    [string]$Prompt,
    [switch]$Run,
    [switch]$SkipInstall,
    [int]$MaxFixAttempts = 3
)

$ErrorActionPreference = 'Stop'

# Ensure UTF-8 output so Claude's response renders correctly
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Allow running inside another Claude Code session
$env:CLAUDECODE = $null

$knowledgeFile = "$PSScriptRoot\IvyPlaywrightKnowledge.md"
$projectRoot = (Get-Location).Path
$testsDir = Join-Path $projectRoot ".ivy\tests"

# --- Validate we're in an Ivy project ---

$csprojFiles = Get-ChildItem -Path $projectRoot -Filter "*.csproj" -File
if ($csprojFiles.Count -eq 0) {
    Write-Host "No .csproj file found. Run this from an Ivy project folder." -ForegroundColor Red
    exit 1
}

$programCs = Join-Path $projectRoot "Program.cs"
if (-not (Test-Path $programCs)) {
    Write-Host "No Program.cs found. Run this from an Ivy project folder." -ForegroundColor Red
    exit 1
}

$projectName = $csprojFiles[0].BaseName

Write-Host "Ivy Project: $projectName" -ForegroundColor Cyan
Write-Host "Project Root: $projectRoot" -ForegroundColor DarkGray

# --- Collect project source files ---

Write-Host "`nCollecting source files..." -ForegroundColor Yellow

$sourceFiles = @()
$sourceFiles += Get-ChildItem -Path $projectRoot -Filter "*.cs" -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\(bin|obj|\.ivy)\\' }
$sourceFiles += Get-ChildItem -Path $projectRoot -Filter "*.csproj" -File

$sourceContext = ""
foreach ($file in $sourceFiles) {
    $relativePath = $file.FullName.Replace($projectRoot, "").TrimStart("\", "/")
    $content = Get-Content $file.FullName -Raw
    $sourceContext += "`n### File: $relativePath`n``````csharp`n$content`n```````n"
}

Write-Host "  Found $($sourceFiles.Count) source file(s)" -ForegroundColor Green

# --- Load knowledge base ---

$knowledge = ""
if (Test-Path $knowledgeFile) {
    $knowledge = Get-Content $knowledgeFile -Raw
    Write-Host "  Loaded knowledge base ($((Get-Item $knowledgeFile).Length) bytes)" -ForegroundColor Green
} else {
    Write-Host "  No knowledge base found, starting fresh" -ForegroundColor Yellow
}

# --- Load existing tests and previous run artifacts ---

$existingTests = ""
$existingTestFiles = Get-ChildItem -Path $testsDir -Filter "*.spec.ts" -File -ErrorAction SilentlyContinue
if ($existingTestFiles) {
    foreach ($tf in $existingTestFiles) {
        $relativePath = $tf.FullName.Replace($projectRoot, "").TrimStart("\", "/")
        $content = Get-Content $tf.FullName -Raw
        $existingTests += "`n### File: $relativePath`n``````typescript`n$content`n```````n"
    }
    Write-Host "  Found $($existingTestFiles.Count) existing test file(s)" -ForegroundColor Green
}

$previousReview = ""
$reviewFile = Join-Path $testsDir "review.md"
if (Test-Path $reviewFile) {
    $previousReview = Get-Content $reviewFile -Raw
    Write-Host "  Loaded previous review (issues to address)" -ForegroundColor Green
}

$previousConsoleLogs = ""
$consoleLogFile = Join-Path $testsDir "console.log"
if (Test-Path $consoleLogFile) {
    $previousConsoleLogs = Get-Content $consoleLogFile -Raw
    Write-Host "  Loaded previous console log" -ForegroundColor Green
}

$previousBackendLogs = ""
$backendLogFile = Join-Path $testsDir "backend.log"
if (Test-Path $backendLogFile) {
    $previousBackendLogs = Get-Content $backendLogFile -Raw
    Write-Host "  Loaded previous backend log" -ForegroundColor Green
}

# --- Ensure tests and screenshots directories exist ---

$screenshotsDir = Join-Path $testsDir "screenshots"
New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
New-Item -ItemType Directory -Path $screenshotsDir -Force | Out-Null

# --- Build the prompt ---

$generatePrompt = @"
You are generating Playwright end-to-end tests for an Ivy Framework .NET web application.
Write the files directly to disk. Do not output file contents as text — use your Write tool.

## Knowledge Base (learnings from previous runs)
$knowledge

## Project Source Code
$sourceContext

## Existing Tests (if any — improve or extend, do not duplicate)
$existingTests

$(if ($previousReview) { "## Previous Review (issues found in last run — address these)`n$previousReview" })

$(if ($previousConsoleLogs) { "## Previous Console Logs`n``````n$previousConsoleLogs``````" })

$(if ($previousBackendLogs) { "## Previous Backend Logs`n``````n$previousBackendLogs``````" })

## Instructions

Generate comprehensive Playwright tests for this Ivy project.
Write each file directly to the .ivy/tests/ directory at: $testsDir

### Files to create:

1. **$testsDir\package.json** — minimal, with @playwright/test dependency
2. **$testsDir\playwright.config.ts** — Chromium only, single worker, uses APP_PORT env var
3. **$testsDir\<app-name>.spec.ts** — one spec file per app found in the source code

### Test file structure:
- beforeAll: find free port, spawn dotnet run, wait for server ready
- afterAll: kill process
- beforeEach: navigate to root
- Tests should cover:
  - All UI elements are visible (text, labels, buttons, inputs)
  - Interactive elements work (buttons click, switches toggle, sliders move)
  - State changes are reflected in the UI
  - Edge cases specific to the app's logic
  - Generated/computed output appears correctly

### Screenshots:
- Save screenshots to: $screenshotsDir
- Take a screenshot at EVERY important step:
  - After initial page load (e.g. "01-initial-load.png")
  - After each major interaction (e.g. "02-after-generate-click.png", "03-after-toggle-switch.png")
  - When output/results appear (e.g. "04-password-generated.png")
  - After edge case scenarios (e.g. "05-all-switches-off.png")
- Use descriptive numbered filenames so they sort chronologically
- Use: await page.screenshot({ path: "<screenshots-dir>/<name>.png", fullPage: true })
- Keep a global screenshot counter across all tests to maintain ordering

### Logging:
- Capture browser console logs and write them to: $testsDir\console.log
- In beforeEach, attach a listener: page.on("console", msg => ...) that appends each message to an array
- In afterAll, write all collected console messages to the log file
- Also capture the dotnet process stdout/stderr and write to: $testsDir\backend.log

### Code style:
- TypeScript, clean imports
- Use getByText(), getByRole() locators (prefer accessibility-friendly locators)
- Use .first() when multiple matches possible
- Use waitForTimeout(500) after interactions before asserting
- On Windows use shell: true in spawn options
- Resolve project root from test dir: process.cwd().replace(/[/\\]\.ivy[/\\]tests$/, "")

$(if ($Prompt) { "## Additional Instructions from User`n$Prompt" })

Write all files now.
"@

# --- Call Claude to generate tests (writes files directly) ---

Write-Host "`nGenerating tests with Claude..." -ForegroundColor Yellow

& claude -p $generatePrompt --dangerously-skip-permissions --verbose 2>&1 | Out-Host

if ($LASTEXITCODE -ne 0) {
    Write-Host "Claude failed to generate tests." -ForegroundColor Red
    exit 1
}

# --- Verify files were created ---

$generatedFiles = @()
$generatedFiles += Get-ChildItem -Path $testsDir -Filter "package.json" -File -ErrorAction SilentlyContinue
$generatedFiles += Get-ChildItem -Path $testsDir -Filter "playwright.config.ts" -File -ErrorAction SilentlyContinue
$generatedFiles += Get-ChildItem -Path $testsDir -Filter "*.spec.ts" -File -ErrorAction SilentlyContinue

if ($generatedFiles.Count -eq 0) {
    Write-Host "No test files were generated." -ForegroundColor Red
    exit 1
}

$generatedNames = $generatedFiles | ForEach-Object { $_.Name }
Write-Host "`nGenerated $($generatedFiles.Count) file(s): $($generatedNames -join ', ')" -ForegroundColor Green

# --- Install dependencies ---

if (-not $SkipInstall) {
    Write-Host "`nInstalling dependencies..." -ForegroundColor Yellow
    Push-Location $testsDir

    npm install 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "npm install failed" -ForegroundColor Red
        Pop-Location
        exit 1
    }

    # Ensure Playwright browsers are installed
    $chromiumPath = "$env:LOCALAPPDATA\ms-playwright"
    if (-not (Test-Path "$chromiumPath\chromium-*")) {
        Write-Host "  Installing Playwright browsers..." -ForegroundColor Yellow
        npx playwright install chromium 2>&1 | Out-Null
    }

    Pop-Location
    Write-Host "  Dependencies ready" -ForegroundColor Green
}

# --- Run tests ---

if (-not $Run) {
    Write-Host "`nTests generated. Use -Run to also execute them." -ForegroundColor Cyan
    Write-Host "  cd .ivy/tests && npx playwright test" -ForegroundColor DarkGray
    exit 0
}

# Clean previous screenshots and logs before running
Get-ChildItem -Path $screenshotsDir -Filter "*.png" -File -ErrorAction SilentlyContinue | Remove-Item -Force
Remove-Item -Path (Join-Path $testsDir "console.log") -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $testsDir "backend.log") -ErrorAction SilentlyContinue

Write-Host "`nRunning tests..." -ForegroundColor Yellow

$attempt = 0
$testsPassed = $false
$fixHistory = @()

while ($attempt -lt ($MaxFixAttempts + 1)) {
    Push-Location $testsDir
    $testOutput = & npx playwright test 2>&1 | Out-String
    $testExitCode = $LASTEXITCODE
    Pop-Location

    if ($testExitCode -eq 0) {
        Write-Host $testOutput
        Write-Host "`nAll tests passed!" -ForegroundColor Green
        $testsPassed = $true
        break
    }

    $attempt++
    Write-Host $testOutput

    if ($attempt -gt $MaxFixAttempts) {
        Write-Host "`nTests still failing after $MaxFixAttempts fix attempts." -ForegroundColor Red
        break
    }

    Write-Host "`nTests failed (attempt $attempt/$MaxFixAttempts). Asking Claude to fix..." -ForegroundColor Yellow

    # Snapshot Ivy source files before the fix
    $beforeFixSource = @{}
    foreach ($file in $sourceFiles) {
        $beforeFixSource[$file.FullName] = Get-Content $file.FullName -Raw
    }

    # Collect current test files for the fix prompt
    $currentTestCode = ""
    $specFiles = Get-ChildItem -Path $testsDir -Filter "*.spec.ts" -File -ErrorAction SilentlyContinue
    foreach ($sf in $specFiles) {
        $content = Get-Content $sf.FullName -Raw
        $currentTestCode += "`n### File: $($sf.Name)`n``````typescript`n$content`n```````n"
    }

    $fixPrompt = @"
The Playwright tests for this Ivy project are failing. Fix them by writing corrected files directly to disk.

## Test Output (errors)
``````
$testOutput
``````

## Current Test Code
$currentTestCode

## Project Source Code
$sourceContext

## Knowledge Base
$knowledge

## Instructions
- Analyze the errors — determine if the issue is in the test code OR the Ivy project source code
- If the Ivy source code has bugs, fix the .cs files in: $projectRoot
- If the test code has wrong selectors or timing issues, fix the .spec.ts files in: $testsDir
- Use your Write/Edit tools to write corrected files directly
- Do not change package.json or playwright.config.ts unless they are the cause
- Keep tests that pass, only fix what's broken
"@

    & claude -p $fixPrompt --dangerously-skip-permissions --verbose 2>&1 | Out-Host

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Claude failed to fix tests" -ForegroundColor Red
        break
    }

    # Record changes to Ivy source files (not test files)
    $roundChanges = @()
    foreach ($file in $sourceFiles) {
        $afterContent = Get-Content $file.FullName -Raw
        $relativePath = $file.FullName.Replace($projectRoot, "").TrimStart("\", "/")
        if ($beforeFixSource[$file.FullName] -ne $afterContent) {
            # Generate a simple diff summary
            $beforeLines = ($beforeFixSource[$file.FullName] -split "`n").Count
            $afterLines = ($afterContent -split "`n").Count
            $roundChanges += "- **$relativePath** ($beforeLines -> $afterLines lines)"
        }
    }
    # Check for new .cs files that didn't exist before
    $currentSourceFiles = Get-ChildItem -Path $projectRoot -Filter "*.cs" -Recurse -File |
        Where-Object { $_.FullName -notmatch '\\(bin|obj|\.ivy)\\' }
    foreach ($file in $currentSourceFiles) {
        if (-not $beforeFixSource.ContainsKey($file.FullName)) {
            $relativePath = $file.FullName.Replace($projectRoot, "").TrimStart("\", "/")
            $roundChanges += "- **$relativePath** (new file)"
        }
    }

    if ($roundChanges.Count -gt 0) {
        $fixHistory += [PSCustomObject]@{
            Round      = $attempt
            Errors     = ($testOutput -split "`n" | Where-Object { $_ -match '(Error|FAILED|✘)' } | ForEach-Object { $_.Trim() }) -join "`n"
            Changes    = $roundChanges -join "`n"
        }
    }
}

# --- Write fixes.md if any Ivy source fixes were made ---

if ($fixHistory.Count -gt 0) {
    Write-Host "`nDocumenting Ivy code fixes..." -ForegroundColor Yellow

    $fixesMd = "# Ivy Code Fixes`n`n"
    $fixesMd += "Fixes applied to the Ivy project source code to make tests pass.`n`n"
    $fixesMd += "**Project:** $projectName`n"
    $fixesMd += "**Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n"
    $fixesMd += "**Fix rounds with source changes:** $($fixHistory.Count)`n"
    $fixesMd += "**Final result:** $(if ($testsPassed) { 'PASSED' } else { 'FAILED' })`n"
    $fixesMd += "`n---`n"

    foreach ($fix in $fixHistory) {
        $fixesMd += "`n## Round $($fix.Round)`n"
        $fixesMd += "`n### Test errors that triggered the fix`n``````n$($fix.Errors)`n```````n"
        $fixesMd += "`n### Source files changed`n$($fix.Changes)`n"
    }

    $fixesFile = Join-Path $testsDir "fixes.md"
    Set-Content -Path $fixesFile -Value $fixesMd -Encoding UTF8
    Write-Host "  Written: .ivy/tests/fixes.md" -ForegroundColor Green
}

# --- Verify screenshots and logs ---

if ($testsPassed) {
    $screenshots = Get-ChildItem -Path $screenshotsDir -Filter "*.png" -File -ErrorAction SilentlyContinue
    $consoleLog = Join-Path $testsDir "console.log"
    $backendLog = Join-Path $testsDir "backend.log"

    if ($screenshots.Count -gt 0) {
        Write-Host "`nVerifying $($screenshots.Count) screenshot(s) and logs with Claude..." -ForegroundColor Yellow

        # Build file list for Claude to read
        $screenshotPaths = ($screenshots | ForEach-Object { $_.FullName }) -join "`n"

        $logContext = ""
        if (Test-Path $consoleLog) {
            $logContext += "`n## Browser Console Log`n``````n$(Get-Content $consoleLog -Raw)``````n"
        }
        if (Test-Path $backendLog) {
            $logContext += "`n## Backend Log (dotnet)`n``````n$(Get-Content $backendLog -Raw)``````n"
        }

        $verifyPrompt = @"
You are reviewing screenshots and logs from a Playwright test run of an Ivy Framework app.

## Project: $projectName

## Screenshots to review (read each image file):
$screenshotPaths

## Logs
$logContext

## Instructions
For each screenshot, use your Read tool to view it, then check:
1. Does the UI render correctly? (no blank pages, no broken layouts, no missing components)
2. Are there any visible error messages, stack traces, or exception dialogs?
3. Does the app look functional and polished?

For the logs, check:
1. Are there any runtime errors, unhandled exceptions, or warnings in the browser console?
2. Are there any errors or stack traces in the backend log?
3. Any deprecation warnings or performance issues?

Output a structured report:

### Screenshots
For each screenshot: OK or ISSUE with a brief description.

### Console Log
OK or list of issues found.

### Backend Log
OK or list of issues found.

### Overall Verdict
PASS — if everything looks good
ISSUES FOUND — if there are problems, with a summary
"@

        $verifyResult = & claude -p $verifyPrompt --dangerously-skip-permissions --verbose 2>&1 | Out-String
        $verifyResult = $verifyResult.Trim()

        Write-Host $verifyResult

        if ($verifyResult -match 'ISSUES FOUND') {
            Write-Host "`nScreenshot/log review found issues!" -ForegroundColor Yellow
            $screenshotReport = Join-Path $testsDir "review.md"
            $reportContent = "# Screenshot & Log Review`n`n"
            $reportContent += "**Project:** $projectName`n"
            $reportContent += "**Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n"
            $reportContent += "**Screenshots reviewed:** $($screenshots.Count)`n`n"
            $reportContent += "---`n`n"
            $reportContent += $verifyResult
            Set-Content -Path $screenshotReport -Value $reportContent -Encoding UTF8
            Write-Host "  Written: .ivy/tests/review.md" -ForegroundColor Green
        } else {
            Write-Host "`nScreenshot and log review: all OK" -ForegroundColor Green
        }
    } else {
        Write-Host "`nNo screenshots found to verify" -ForegroundColor Yellow
    }
}

# --- Self-improvement: extract learnings ---

if ($testsPassed) {
    Write-Host "`nExtracting learnings for knowledge base..." -ForegroundColor Yellow

    # Gather final test code
    $finalTestCode = ""
    $finalSpecFiles = Get-ChildItem -Path $testsDir -Filter "*.spec.ts" -File -ErrorAction SilentlyContinue
    foreach ($sf in $finalSpecFiles) {
        $content = Get-Content $sf.FullName -Raw
        $finalTestCode += "`n### $($sf.Name)`n``````typescript`n$content`n```````n"
    }

    $learningPrompt = @"
Analyze this successful Playwright test run for an Ivy Framework project and extract NEW learnings.

## Project Source
$sourceContext

## Final Working Tests
$finalTestCode

## Fix Attempts Made: $attempt

## Existing Knowledge Base
$knowledge

## Instructions
Output a SHORT bullet list (3-8 items max) of NEW insights not already in the knowledge base.
Focus on:
- Ivy-specific patterns discovered (component rendering, selectors that work)
- Locator strategies that succeeded or failed
- Timing/wait patterns needed
- Any fixes that were needed and why

If there are no new learnings, output exactly: NO_NEW_LEARNINGS

Format each learning as: - <learning>
Output ONLY the bullet list, no other text.
"@

    $learnings = & claude -p $learningPrompt --dangerously-skip-permissions --verbose 2>&1 | Out-String
    $learnings = $learnings.Trim()

    if ($learnings -ne "NO_NEW_LEARNINGS" -and $learnings.Length -gt 10) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
        $entry = "`n### $timestamp — $projectName`n$learnings`n"

        Add-Content -Path $knowledgeFile -Value $entry -Encoding UTF8
        Write-Host "  Knowledge base updated with new learnings" -ForegroundColor Green
    } else {
        Write-Host "  No new learnings to add" -ForegroundColor DarkGray
    }
}

# --- Write report.md ---

Write-Host "`nWriting report..." -ForegroundColor Yellow

$result = if ($testsPassed) { 'PASSED' } elseif ($Run) { 'FAILED' } else { 'NOT RUN' }

$reportMd = "# Test Report`n`n"
$reportMd += "**Project:** $projectName`n"
$reportMd += "**Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n"
$reportMd += "**Result:** $result`n"
$reportMd += "**Generated files:** $($generatedNames -join ', ')`n"
if ($attempt -gt 0 -and $Run) {
    $reportMd += "**Fix rounds:** $attempt`n"
}
$reportMd += "`n---`n"

# Source files section
$reportMd += "`n## Source Files`n`n"
$reportMd += "$($sourceFiles.Count) file(s) collected.`n"

# Test generation section
$reportMd += "`n## Generated Tests`n`n"
foreach ($name in $generatedNames) {
    $reportMd += "- $name`n"
}

# Fixes section (inline from fix history)
if ($fixHistory.Count -gt 0) {
    $reportMd += "`n## Fixes Applied`n`n"
    $reportMd += "$($fixHistory.Count) round(s) required source code changes.`n"
    foreach ($fix in $fixHistory) {
        $reportMd += "`n### Round $($fix.Round)`n"
        $reportMd += "`n#### Errors`n``````n$($fix.Errors)`n```````n"
        $reportMd += "`n#### Changes`n$($fix.Changes)`n"
    }
}

# Screenshots section
if ($Run -and $testsPassed) {
    $screenshots = Get-ChildItem -Path $screenshotsDir -Filter "*.png" -File -ErrorAction SilentlyContinue
    if ($screenshots.Count -gt 0) {
        $reportMd += "`n## Screenshots`n`n"
        $reportMd += "$($screenshots.Count) screenshot(s) captured.`n`n"
        foreach ($s in $screenshots) {
            $reportMd += "- $($s.Name)`n"
        }
    }
}

# Review section (if review.md was written this run)
$reviewFile = Join-Path $testsDir "review.md"
if (Test-Path $reviewFile) {
    $reportMd += "`n## Review`n`n"
    $reportMd += "See [review.md](review.md) for screenshot and log review details.`n"
}

$reportFile = Join-Path $testsDir "report.md"
Set-Content -Path $reportFile -Value $reportMd -Encoding UTF8
Write-Host "  Written: .ivy/tests/report.md" -ForegroundColor Green

# --- Summary ---

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Project:    $projectName" -ForegroundColor White
Write-Host "  Tests Dir:  .ivy/tests/" -ForegroundColor White
Write-Host "  Files:      $($generatedNames -join ', ')" -ForegroundColor White
Write-Host "  Result:     $(if ($testsPassed) { 'PASSED' } elseif ($Run) { 'FAILED' } else { 'NOT RUN' })" -ForegroundColor $(if ($testsPassed) { 'Green' } elseif ($Run) { 'Red' } else { 'Yellow' })
if ($attempt -gt 0 -and $Run) {
    Write-Host "  Fix Rounds: $attempt" -ForegroundColor White
}
Write-Host "========================================" -ForegroundColor Cyan
