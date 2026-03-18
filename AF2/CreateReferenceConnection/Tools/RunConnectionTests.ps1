<#
.SYNOPSIS
    Orchestrates the full test suite for an Ivy connection implementation.

.DESCRIPTION
    This script creates a temp test directory, copies the connection project,
    sets up Playwright tests, runs all test categories, collects results,
    and generates a comprehensive test report.

.PARAMETER ServiceName
    The name of the service/connection to test (e.g., "Claude", "Stripe")

.PARAMETER ConnectionPath
    Optional. Path to the connection directory. Defaults to D:\Repos\_Ivy\Ivy\connections\<ServiceName>

.PARAMETER TestDir
    Optional. Path to test directory. Defaults to D:\Temp\CreateReferenceConnectionTest\<ServiceName>

.PARAMETER MaxRetries
    Optional. Maximum number of fix/retry cycles. Defaults to 5.

.EXAMPLE
    .\RunConnectionTests.ps1 -ServiceName "Claude"

.EXAMPLE
    .\RunConnectionTests.ps1 -ServiceName "Stripe" -MaxRetries 3
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ServiceName,

    [Parameter(Mandatory=$false)]
    [string]$ConnectionPath = "",

    [Parameter(Mandatory=$false)]
    [string]$TestDir = "",

    [Parameter(Mandatory=$false)]
    [int]$MaxRetries = 5
)

$ErrorActionPreference = "Stop"

# Set default paths if not provided
if ([string]::IsNullOrEmpty($ConnectionPath)) {
    $ConnectionPath = "D:\Repos\_Ivy\Ivy\connections\$ServiceName"
}

if ([string]::IsNullOrEmpty($TestDir)) {
    $TestDir = "D:\Temp\CreateReferenceConnectionTest\$ServiceName"
}

$ProjectPath = "$ConnectionPath\Ivy.Connections.$ServiceName"
$TestResultsPath = "$TestDir\.ivy\tests"

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  Connection Test Runner" -ForegroundColor Cyan
Write-Host "  Service: $ServiceName" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Validate connection exists
if (-not (Test-Path $ConnectionPath)) {
    Write-Host "ERROR: Connection directory not found: $ConnectionPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $ProjectPath)) {
    Write-Host "ERROR: Project directory not found: $ProjectPath" -ForegroundColor Red
    exit 1
}

# Step 1: Create test directory structure
Write-Host "[1/7] Creating test directory..." -ForegroundColor Yellow
if (Test-Path $TestDir) {
    Write-Host "  Cleaning existing test directory..." -ForegroundColor Gray
    Remove-Item -Path $TestDir -Recurse -Force
}

New-Item -Path $TestDir -ItemType Directory -Force | Out-Null
New-Item -Path "$TestResultsPath\screenshots" -ItemType Directory -Force | Out-Null
Write-Host "  ✓ Test directory created: $TestDir" -ForegroundColor Green

# Step 2: Copy connection project
Write-Host "[2/7] Copying connection project..." -ForegroundColor Yellow
Copy-Item -Path $ProjectPath -Destination "$TestDir\Ivy.Connections.$ServiceName" -Recurse -Force
Write-Host "  ✓ Connection project copied" -ForegroundColor Green

# Step 3: Set up Playwright tests
Write-Host "[3/7] Setting up Playwright tests..." -ForegroundColor Yellow
$CreatePlaywrightScript = Join-Path $PSScriptRoot "CreatePlaywrightTests.ps1"
if (-not (Test-Path $CreatePlaywrightScript)) {
    Write-Host "  ERROR: CreatePlaywrightTests.ps1 not found" -ForegroundColor Red
    exit 1
}

& $CreatePlaywrightScript -ServiceName $ServiceName -TestDir $TestDir -ProjectPath "$TestDir\Ivy.Connections.$ServiceName"
Write-Host "  ✓ Playwright tests configured" -ForegroundColor Green

# Step 4: Build Test
Write-Host "[4/7] Running build test..." -ForegroundColor Yellow
$buildOutput = ""
try {
    Push-Location "$TestDir\Ivy.Connections.$ServiceName"
    $buildOutput = dotnet build 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed"
    }
    Write-Host "  ✓ Build succeeded" -ForegroundColor Green
    $buildPassed = $true
} catch {
    Write-Host "  ✗ Build failed" -ForegroundColor Red
    $buildPassed = $false
} finally {
    Pop-Location
}
$buildOutput | Out-File -FilePath "$TestResultsPath\build.log" -Encoding UTF8

# Step 5: Unit Tests
Write-Host "[5/7] Running unit tests..." -ForegroundColor Yellow
$testOutput = ""
$testPassed = $false
$testCount = 0
try {
    Push-Location "$TestDir\Ivy.Connections.$ServiceName"
    $testOutput = dotnet test --no-build --verbosity normal 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        $testPassed = $true
        # Try to extract test count
        if ($testOutput -match "Passed!\s+-\s+Failed:\s+(\d+),\s+Passed:\s+(\d+),\s+Skipped:\s+(\d+)") {
            $testCount = [int]$matches[2]
        }
        Write-Host "  ✓ Unit tests passed ($testCount tests)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Unit tests failed" -ForegroundColor Red
    }
} catch {
    Write-Host "  ✗ Unit tests failed" -ForegroundColor Red
} finally {
    Pop-Location
}
$testOutput | Out-File -FilePath "$TestResultsPath\unit-tests.log" -Encoding UTF8

# Step 6: Playwright Tests
Write-Host "[6/7] Running Playwright tests..." -ForegroundColor Yellow
$playwrightPassed = $false
try {
    Push-Location $TestResultsPath

    # Install Playwright if needed
    if (-not (Test-Path "node_modules")) {
        Write-Host "  Installing Playwright..." -ForegroundColor Gray
        npm install --silent 2>&1 | Out-Null
        npx playwright install chromium --with-deps 2>&1 | Out-Null
    }

    # Run Playwright tests
    $playwrightOutput = npx playwright test --reporter=list 2>&1 | Out-String
    $playwrightOutput | Out-File -FilePath "$TestResultsPath\playwright.log" -Encoding UTF8

    if ($LASTEXITCODE -eq 0) {
        $playwrightPassed = $true
        Write-Host "  ✓ Playwright tests passed" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Playwright tests failed" -ForegroundColor Red
    }
} catch {
    Write-Host "  ✗ Playwright tests failed" -ForegroundColor Red
} finally {
    Pop-Location
}

# Step 7: Analyze results and generate report
Write-Host "[7/7] Generating test report..." -ForegroundColor Yellow
$AnalyzeScript = Join-Path $PSScriptRoot "AnalyzeTestResults.ps1"
if (-not (Test-Path $AnalyzeScript)) {
    Write-Host "  ERROR: AnalyzeTestResults.ps1 not found" -ForegroundColor Red
    exit 1
}

& $AnalyzeScript -ServiceName $ServiceName -TestDir $TestDir

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  Test Report: $TestResultsPath\report.md" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Return exit code based on overall results
if ($buildPassed -and $testPassed -and $playwrightPassed) {
    Write-Host "✓ All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "✗ Some tests failed. Check report for details." -ForegroundColor Red
    exit 1
}
