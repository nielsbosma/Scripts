<#
.SYNOPSIS
    Analyzes test results and generates a comprehensive report.

.DESCRIPTION
    Processes test output from build, unit tests, app launch, and Playwright E2E,
    then generates a markdown summary report including screenshot inventory.

.PARAMETER ServiceName
    The name of the service/connection tested

.PARAMETER TestDir
    The results directory path (contains .ivy/tests/)

.PARAMETER ProjectPath
    Path to the connection project (source directory)

.EXAMPLE
    .\AnalyzeTestResults.ps1 -ServiceName "CoinGecko" -TestDir "D:\Temp\CreateReferenceConnectionTest\CoinGecko" -ProjectPath "D:\Repos\_Ivy\Ivy\connections\CoinGecko\Ivy.Connections.CoinGecko"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ServiceName,

    [Parameter(Mandatory=$true)]
    [string]$TestDir,

    [Parameter(Mandatory=$false)]
    [string]$ProjectPath = ""
)

$ErrorActionPreference = "Stop"
$TestsDir = "$TestDir\.ivy\tests"

if ([string]::IsNullOrEmpty($ProjectPath)) {
    $ProjectPath = "D:\Repos\_Ivy\Ivy\connections\$ServiceName\Ivy.Connections.$ServiceName"
}

function Get-LogStatus {
    param([string]$LogPath, [string]$SuccessPattern)
    if (-not (Test-Path $LogPath)) { return "NOT RUN" }
    $content = Get-Content $LogPath -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($content)) { return "EMPTY" }
    if ($content -match $SuccessPattern) { return "PASS" }
    return "FAIL"
}

# Analyze each phase
$buildStatus = Get-LogStatus "$TestsDir\build.log" "Build succeeded"
$unitTestStatus = Get-LogStatus "$TestsDir\unit-tests.log" "Test Run Successful"
$playwrightStatus = Get-LogStatus "$TestsDir\playwright.log" "passed"

# Unit test count
$unitTestDetails = ""
$unitLog = ""
if (Test-Path "$TestsDir\unit-tests.log") {
    $unitLog = Get-Content "$TestsDir\unit-tests.log" -Raw
    if ($unitLog -match "Total tests:\s+(\d+)") {
        $unitTestDetails = "$($matches[1]) test(s)"
    }
}

# Playwright test count
$playwrightDetails = ""
if (Test-Path "$TestsDir\playwright.log") {
    $pwLog = Get-Content "$TestsDir\playwright.log" -Raw
    if ($pwLog -match "(\d+) passed") {
        $playwrightDetails = "$($matches[1]) test(s) passed"
    }
    if ($pwLog -match "(\d+) failed") {
        $playwrightDetails += ", $($matches[1]) failed"
    }
}

# Connection methods
$connectionFile = "$ProjectPath\Connections\$($ServiceName)Connection.cs"
$methodRows = ""
$methods = @("GetName", "GetConnectionType", "GetEntities", "RegisterServices", "TestConnection", "GetContext", "GetNamespace", "GetSecrets")
if (Test-Path $connectionFile) {
    $content = Get-Content $connectionFile -Raw
    foreach ($m in $methods) {
        $status = if ($content -match $m) { "PRESENT" } else { "MISSING" }
        $methodRows += "| $m | $status |`n"
    }
} else {
    foreach ($m in $methods) {
        $methodRows += "| $m | FILE NOT FOUND |`n"
    }
}

# Screenshots
$screenshotRows = ""
$screenshotFiles = @()
if (Test-Path "$TestsDir\screenshots") {
    $screenshotFiles = Get-ChildItem -Path "$TestsDir\screenshots" -Filter "*.png" -ErrorAction SilentlyContinue | Sort-Object Name
}
if ($screenshotFiles.Count -gt 0) {
    foreach ($s in $screenshotFiles) {
        $sizeKB = [math]::Round($s.Length / 1024, 1)
        $screenshotRows += "| $($s.Name) | ${sizeKB} KB |`n"
    }
} else {
    $screenshotRows = "| (none captured) | - |`n"
}

# Console/backend log analysis
$consoleIssues = ""
if (Test-Path "$TestsDir\console.log") {
    $consoleContent = Get-Content "$TestsDir\console.log" -Raw -ErrorAction SilentlyContinue
    if ($consoleContent) {
        $errors = ($consoleContent -split "`n") | Where-Object { $_ -match "^\[error\]|^\[pageerror\]" } | Where-Object { $_ -notmatch "favicon|DevTools" }
        if ($errors.Count -gt 0) {
            $consoleIssues = "Found $($errors.Count) console error(s):`n" + ($errors | Select-Object -First 5 | ForEach-Object { "- $_" }) -join "`n"
        } else {
            $consoleIssues = "Clean (no errors)"
        }
    } else {
        $consoleIssues = "Empty"
    }
} else {
    $consoleIssues = "Not captured"
}

$backendIssues = ""
if (Test-Path "$TestsDir\backend.log") {
    $backendContent = Get-Content "$TestsDir\backend.log" -Raw -ErrorAction SilentlyContinue
    if ($backendContent) {
        $errors = ($backendContent -split "`n") | Where-Object { $_ -match "exception|unhandled|stack trace" -and $_ -notmatch "^\s*$" }
        if ($errors.Count -gt 0) {
            $backendIssues = "Found $($errors.Count) backend error(s):`n" + ($errors | Select-Object -First 5 | ForEach-Object { "- $_" }) -join "`n"
        } else {
            $backendIssues = "Clean (no exceptions)"
        }
    } else {
        $backendIssues = "Empty"
    }
} else {
    $backendIssues = "Not captured"
}

# Overall result
$allPassed = ($buildStatus -eq "PASS") -and ($unitTestStatus -eq "PASS") -and ($playwrightStatus -eq "PASS")
$overall = if ($allPassed) { "PASS - All tests passed" }
           elseif ($buildStatus -eq "FAIL") { "FAIL - Build failed" }
           else { "PARTIAL - Some tests failed" }

# Generate report
$report = @"
# Connection Test Report: $ServiceName

**Generated:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Result
**$overall**

## Test Results

| Test | Status | Details |
|------|--------|---------|
| Build | $buildStatus | |
| Unit Tests | $unitTestStatus | $unitTestDetails |
| Playwright E2E | $playwrightStatus | $playwrightDetails |

## Connection Interface

| Method | Status |
|--------|--------|
$methodRows
## Screenshots

| File | Size |
|------|------|
$screenshotRows
## Log Review

### Console Logs
$consoleIssues

### Backend Logs
$backendIssues

## Log Files

| Log | Path |
|-----|------|
| Build | $TestsDir\build.log |
| Unit Tests | $TestsDir\unit-tests.log |
| Playwright | $TestsDir\playwright.log |
| Console | $TestsDir\console.log |
| Backend | $TestsDir\backend.log |
| App stdout | $TestsDir\app-stdout.log |
"@

$reportPath = "$TestsDir\report.md"
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "  [DONE] Report: $reportPath" -ForegroundColor Green
