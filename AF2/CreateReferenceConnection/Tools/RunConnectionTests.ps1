<#
.SYNOPSIS
    Orchestrates the full test suite for an Ivy connection implementation.

.DESCRIPTION
    Runs build, unit tests, app launch, and Playwright E2E tests against
    the connection in its source directory.

.PARAMETER ServiceName
    The name of the service/connection to test (e.g., "CoinGecko", "Stripe")

.PARAMETER ConnectionPath
    Optional. Path to the connection directory. Defaults to D:\Repos\_Ivy\Ivy\connections\<ServiceName>

.PARAMETER ResultsDir
    Optional. Path to store test results. Defaults to D:\Temp\CreateReferenceConnectionTest\<ServiceName>

.EXAMPLE
    .\RunConnectionTests.ps1 -ServiceName "CoinGecko"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ServiceName,

    [Parameter(Mandatory=$false)]
    [string]$ConnectionPath = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrEmpty($ConnectionPath)) {
    $ConnectionPath = "D:\Repos\_Ivy\Ivy\connections\$ServiceName"
}

$ProjectPath = "$ConnectionPath\Ivy.Connections.$ServiceName"
$TestsDir = "$ProjectPath\.ivy\tests"

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  Connection Test Runner" -ForegroundColor Cyan
Write-Host "  Service: $ServiceName" -ForegroundColor Cyan
Write-Host "  Source:  $ProjectPath" -ForegroundColor Cyan
Write-Host "  Tests:   $TestsDir" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Validate connection exists
if (-not (Test-Path $ProjectPath)) {
    Write-Host "[FAIL] Project directory not found: $ProjectPath" -ForegroundColor Red
    exit 1
}

# Create test directory structure in-place
if (Test-Path "$TestsDir\screenshots") {
    Remove-Item -Path "$TestsDir\screenshots\*" -Force -ErrorAction SilentlyContinue
}
New-Item -Path "$TestsDir\screenshots" -ItemType Directory -Force | Out-Null
# Clean previous logs
Get-ChildItem -Path $TestsDir -Filter "*.log" -ErrorAction SilentlyContinue | Remove-Item -Force

# Track results
$results = @{
    Build = $false
    UnitTests = $false
    AppLaunch = $false
    Playwright = $false
}

# ---- Step 1: Build ----
Write-Host "[1/4] Building project..." -ForegroundColor Yellow
try {
    Push-Location $ProjectPath
    $buildOutput = dotnet build 2>&1 | Out-String
    $buildOutput | Out-File -FilePath "$TestsDir\build.log" -Encoding UTF8
    if ($LASTEXITCODE -eq 0) {
        $results.Build = $true
        Write-Host "  [PASS] Build succeeded" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Build failed" -ForegroundColor Red
    }
} catch {
    Write-Host "  [FAIL] Build error: $_" -ForegroundColor Red
} finally {
    Pop-Location
}

if (-not $results.Build) {
    Write-Host ""
    Write-Host "[ABORT] Build failed. Cannot continue." -ForegroundColor Red
    & "$PSScriptRoot\AnalyzeTestResults.ps1" -ServiceName $ServiceName -TestDir $ProjectPath -ProjectPath $ProjectPath
    exit 1
}

# ---- Step 2: Unit Tests ----
Write-Host "[2/4] Running unit tests..." -ForegroundColor Yellow
try {
    Push-Location $ProjectPath
    $testOutput = dotnet test --no-build --verbosity normal 2>&1 | Out-String
    $testOutput | Out-File -FilePath "$TestsDir\unit-tests.log" -Encoding UTF8
    if ($LASTEXITCODE -eq 0) {
        $results.UnitTests = $true
        if ($testOutput -match "Total tests:\s+(\d+)") {
            Write-Host "  [PASS] $($matches[1]) test(s) passed" -ForegroundColor Green
        } else {
            Write-Host "  [PASS] Unit tests passed" -ForegroundColor Green
        }
    } else {
        Write-Host "  [FAIL] Unit tests failed" -ForegroundColor Red
    }
} catch {
    Write-Host "  [FAIL] Test error: $_" -ForegroundColor Red
} finally {
    Pop-Location
}

# ---- Step 3: App Launch Smoke Test ----
Write-Host "[3/4] Testing app launch..." -ForegroundColor Yellow
$port = 5199
try {
    Push-Location $ProjectPath
    $appProcess = Start-Process -FilePath "dotnet" -ArgumentList "run", "--no-build", "--", "--port", $port, "--chrome=false" -PassThru -NoNewWindow -RedirectStandardOutput "$TestsDir\app-stdout.log" -RedirectStandardError "$TestsDir\app-stderr.log"

    $started = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 1
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$port" -UseBasicParsing -TimeoutSec 2 -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                $started = $true
                break
            }
        } catch { }
    }

    if ($started) {
        $results.AppLaunch = $true
        Write-Host "  [PASS] App launched on port $port (HTTP 200, $($response.Content.Length) bytes)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] App did not start within 20 seconds" -ForegroundColor Red
    }
} catch {
    Write-Host "  [FAIL] App launch error: $_" -ForegroundColor Red
} finally {
    if ($appProcess -and -not $appProcess.HasExited) {
        Stop-Process -Id $appProcess.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
    Pop-Location
}

# ---- Step 4: Playwright E2E Tests ----
Write-Host "[4/4] Running Playwright E2E tests..." -ForegroundColor Yellow
try {
    & "$PSScriptRoot\CreatePlaywrightTests.ps1" -ServiceName $ServiceName -TestDir $ProjectPath -ProjectPath $ProjectPath

    Push-Location $TestsDir

    # Use Continue for vp/npx - they write to stderr even on success
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    if (-not (Test-Path "node_modules")) {
        Write-Host "  Installing dependencies..." -ForegroundColor Gray
        vp install 2>&1 | Out-Null
        npx playwright install chromium --with-deps 2>&1 | Out-Null
    }

    $playwrightOutput = vp run test -- --reporter=list 2>&1 | Out-String
    $playwrightOutput | Out-File -FilePath "$TestsDir\playwright.log" -Encoding UTF8

    $ErrorActionPreference = $prevPref

    if ($LASTEXITCODE -eq 0) {
        $results.Playwright = $true
        Write-Host "  [PASS] Playwright tests passed" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Playwright tests failed" -ForegroundColor Red
        Write-Host $playwrightOutput -ForegroundColor Gray
    }
} catch {
    Write-Host "  [SKIP] Playwright error: $_" -ForegroundColor Yellow
} finally {
    $ErrorActionPreference = "Stop"
    Pop-Location 2>$null
}

# ---- Generate Report ----
Write-Host ""
Write-Host "Generating report..." -ForegroundColor Yellow
& "$PSScriptRoot\AnalyzeTestResults.ps1" -ServiceName $ServiceName -TestDir $ProjectPath -ProjectPath $ProjectPath

# ---- Summary ----
Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
$passed = ($results.Values | Where-Object { $_ }).Count
$total = $results.Count
Write-Host "  Results: $passed/$total passed" -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Yellow" })
Write-Host "  Report:  $TestsDir\report.md" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

if ($passed -eq $total) { exit 0 } else { exit 1 }
