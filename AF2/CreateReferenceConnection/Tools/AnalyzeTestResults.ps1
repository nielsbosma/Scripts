<#
.SYNOPSIS
    Analyzes test results and generates a comprehensive report.

.DESCRIPTION
    Processes test output, analyzes screenshots, reviews log files,
    and generates a markdown summary report.

.PARAMETER ServiceName
    The name of the service/connection tested

.PARAMETER TestDir
    The test directory path

.EXAMPLE
    .\AnalyzeTestResults.ps1 -ServiceName "Claude" -TestDir "D:\Temp\CreateReferenceConnectionTest\Claude"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ServiceName,

    [Parameter(Mandatory=$true)]
    [string]$TestDir
)

$ErrorActionPreference = "Stop"
$TestsDir = "$TestDir\.ivy\tests"

# Helper function to determine pass/fail status
function Get-TestStatus {
    param([string]$LogPath, [string]$Pattern)

    if (-not (Test-Path $LogPath)) {
        return "Not Run"
    }

    $content = Get-Content $LogPath -Raw
    if ($content -match $Pattern) {
        return "✅ Pass"
    } else {
        return "❌ Fail"
    }
}

# Helper function to extract test count
function Get-TestCount {
    param([string]$LogPath)

    if (-not (Test-Path $LogPath)) {
        return "N/A"
    }

    $content = Get-Content $LogPath -Raw
    if ($content -match "Passed!\s+-\s+Failed:\s+(\d+),\s+Passed:\s+(\d+),\s+Skipped:\s+(\d+)") {
        return "$($matches[2]) passed, $($matches[1]) failed, $($matches[3]) skipped"
    }

    return "Unable to parse"
}

# Helper function to analyze screenshot
function Test-Screenshot {
    param([string]$ScreenshotPath)

    if (-not (Test-Path $ScreenshotPath)) {
        return "❌ Missing"
    }

    $fileInfo = Get-Item $ScreenshotPath
    if ($fileInfo.Length -lt 1KB) {
        return "⚠️ Too small"
    }

    return "✅ Present"
}

# Analyze build results
$buildStatus = Get-TestStatus -LogPath "$TestsDir\build.log" -Pattern "Build succeeded"
$buildDetails = ""
if (Test-Path "$TestsDir\build.log") {
    $buildLog = Get-Content "$TestsDir\build.log" -Raw
    if ($buildLog -match "(\d+) Error\(s\)") {
        $errorCount = $matches[1]
        if ($errorCount -ne "0") {
            $buildDetails = "$errorCount error(s) found"
        }
    }
}

# Analyze unit test results
$unitTestStatus = Get-TestStatus -LogPath "$TestsDir\unit-tests.log" -Pattern "Passed!"
$unitTestDetails = Get-TestCount -LogPath "$TestsDir\unit-tests.log"

# Analyze Playwright results
$playwrightStatus = Get-TestStatus -LogPath "$TestsDir\playwright.log" -Pattern "passed"
$playwrightDetails = ""
if (Test-Path "$TestsDir\playwright.log") {
    $playwrightLog = Get-Content "$TestsDir\playwright.log" -Raw
    if ($playwrightLog -match "(\d+) passed") {
        $playwrightDetails = "$($matches[1]) test(s) passed"
    }
}

# Analyze demo app screenshots
$screenshots = @()
if (Test-Path "$TestsDir\screenshots") {
    $screenshots = Get-ChildItem -Path "$TestsDir\screenshots" -Filter "*.png" | ForEach-Object {
        @{
            App = $_.BaseName
            Status = Test-Screenshot -ScreenshotPath $_.FullName
            Path = $_.FullName
        }
    }
}

# Check for common connection methods
$projectPath = "$TestDir\Ivy.Connections.$ServiceName"
$connectionFile = "$projectPath\Connections\$($ServiceName)Connection.cs"
$connectionMethods = @{
    GetName = "Not Found"
    GetConnectionType = "Not Found"
    GetSecrets = "Not Found"
    GetEntities = "Not Found"
    RegisterServices = "Not Found"
    TestConnection = "Not Found"
}

if (Test-Path $connectionFile) {
    $connectionContent = Get-Content $connectionFile -Raw
    foreach ($method in $connectionMethods.Keys) {
        if ($connectionContent -match "public.*\s+$method\s*\(") {
            $connectionMethods[$method] = "✅ Present"
        }
    }
}

# Determine overall result
$overallResult = "✅ All tests passed"
if ($buildStatus -like "*Fail*" -or $unitTestStatus -like "*Fail*" -or $playwrightStatus -like "*Fail*") {
    $overallResult = "❌ Failed"
} elseif ($buildStatus -like "*Not Run*" -or $unitTestStatus -like "*Not Run*") {
    $overallResult = "⚠️ Partial"
}

# Extract issues from logs
$issues = @()

# Check build log for errors
if (Test-Path "$TestsDir\build.log") {
    $buildLog = Get-Content "$TestsDir\build.log" -Raw
    $errorMatches = [regex]::Matches($buildLog, "error\s+([A-Z0-9]+):\s+(.+?)(?=\r?\n|$)")
    foreach ($match in $errorMatches) {
        $issues += @{
            Issue = $match.Groups[2].Value
            Severity = "High"
            Area = "Build"
            Details = $match.Groups[1].Value
        }
    }
}

# Check unit test log for failures
if (Test-Path "$TestsDir\unit-tests.log") {
    $testLog = Get-Content "$TestsDir\unit-tests.log" -Raw
    if ($testLog -match "Failed!\s+-\s+Failed:\s+(\d+)") {
        $failedCount = $matches[1]
        if ([int]$failedCount -gt 0) {
            $issues += @{
                Issue = "$failedCount unit test(s) failed"
                Severity = "High"
                Area = "Unit Tests"
                Details = "Check unit-tests.log for details"
            }
        }
    }
}

# Generate report
$report = @"
# Connection Test Report: $ServiceName

**Generated:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Result
$overallResult

## Build Status
**Status:** $buildStatus
$(if ($buildDetails) { "**Details:** $buildDetails" })

## Unit Tests
**Status:** $unitTestStatus
**Details:** $unitTestDetails

## Playwright Tests
**Status:** $playwrightStatus
$(if ($playwrightDetails) { "**Details:** $playwrightDetails" })

## Connection Interface

| Method | Status | Notes |
|--------|--------|-------|
| GetName | $($connectionMethods.GetName) | Returns connection name |
| GetConnectionType | $($connectionMethods.GetConnectionType) | Returns connection type |
| GetSecrets | $($connectionMethods.GetSecrets) | Returns required secrets |
| GetEntities | $($connectionMethods.GetEntities) | Returns available entities |
| RegisterServices | $($connectionMethods.RegisterServices) | Registers DI services |
| TestConnection | $($connectionMethods.TestConnection) | Tests connection validity |

## Demo Apps

| App | Screenshot | Path |
|-----|------------|------|
"@

foreach ($screenshot in $screenshots) {
    $report += "`n| $($screenshot.App) | $($screenshot.Status) | ``$($screenshot.Path)`` |"
}

if ($screenshots.Count -eq 0) {
    $report += "`n| (no apps found) | - | - |"
}

$report += @"


## Issues Found

| Issue | Severity | Area | Details |
|-------|----------|------|---------|
"@

foreach ($issue in $issues) {
    $report += "`n| $($issue.Issue) | $($issue.Severity) | $($issue.Area) | $($issue.Details) |"
}

if ($issues.Count -eq 0) {
    $report += "`n| (no issues detected) | - | - | - |"
}

$report += @"


## Log Files

- **Build Log:** ``$TestsDir\build.log``
- **Unit Test Log:** ``$TestsDir\unit-tests.log``
- **Playwright Log:** ``$TestsDir\playwright.log``

## Recommendations

"@

# Add recommendations based on issues
if ($issues.Count -eq 0) {
    $report += "- All tests passed successfully. Connection is ready for use.`n"
} else {
    $report += "- Review the issues found above and address each one.`n"
}

if ($buildStatus -like "*Fail*") {
    $report += "- Fix build errors before proceeding with further testing.`n"
}

if ($unitTestStatus -like "*Fail*") {
    $report += "- Address failing unit tests to ensure connection reliability.`n"
}

if ($screenshots.Count -eq 0) {
    $report += "- No demo apps found. Consider adding example apps to demonstrate connection usage.`n"
}

# Write report
$reportPath = "$TestsDir\report.md"
$report | Out-File -FilePath $reportPath -Encoding UTF8

Write-Host "  ✓ Test report generated: $reportPath" -ForegroundColor Green
