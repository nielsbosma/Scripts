[CmdletBinding(SupportsShouldProcess)]
param(
    [int]$MaxRetries = 2
)

$ErrorActionPreference = 'Continue'

$repos = @(
    "D:\Repos\_Ivy\Ivy-Agent",
    "D:\Repos\_Ivy\Ivy",
    "D:\Repos\_Ivy\Ivy-Framework",
    "D:\Repos\_Ivy\Ivy-Mcp"
)

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = "D:\Repos\_Personal\Scripts\BuildReport-$timestamp.log"
$results = @()

function Parse-BuildOutput {
    param([string[]]$Output)

    $errors = @()
    $warnings = @()

    foreach ($line in $Output) {
        if ($line -match ': error ') {
            $errors += $line.Trim()
        }
        elseif ($line -match ': warning ') {
            $warnings += $line.Trim()
        }
    }

    # Deduplicate
    $errors = @($errors | Select-Object -Unique)
    $warnings = @($warnings | Select-Object -Unique)

    return @{ Errors = $errors; Warnings = $warnings }
}

function Build-Solution {
    param([string]$SlnxPath)

    $slnDir = Split-Path $SlnxPath -Parent
    $slnName = Split-Path $SlnxPath -Leaf

    Write-Host "  Building $slnName..." -ForegroundColor Cyan

    $buildOutput = & dotnet build $SlnxPath 2>&1
    $buildLines = $buildOutput | ForEach-Object { "$_" }

    $parsed = Parse-BuildOutput -Output $buildLines
    $success = $LASTEXITCODE -eq 0

    return @{
        Solution = $SlnxPath
        SolutionName = $slnName
        Errors = $parsed.Errors
        Warnings = $parsed.Warnings
        Success = $success
        BuildOutput = $buildLines
    }
}

# ── Step A: Discover and build all solutions ──

Write-Host "`n=== DISCOVERING AND BUILDING ALL SOLUTIONS ===" -ForegroundColor Yellow

foreach ($repo in $repos) {
    $repoName = Split-Path $repo -Leaf
    Write-Host "`n[$repoName]" -ForegroundColor Magenta

    if (-not (Test-Path $repo)) {
        Write-Host "  Repo not found at $repo, skipping." -ForegroundColor Red
        continue
    }

    $slnxFiles = Get-ChildItem -Path $repo -Recurse -Filter *.slnx -File | Select-Object -ExpandProperty FullName

    if (-not $slnxFiles) {
        Write-Host "  No .slnx files found." -ForegroundColor DarkGray
        continue
    }

    foreach ($slnx in $slnxFiles) {
        $result = Build-Solution -SlnxPath $slnx
        $result.Repo = $repoName
        $results += $result

        $errCount = $result.Errors.Count
        $warnCount = $result.Warnings.Count
        if ($errCount -eq 0 -and $warnCount -eq 0) {
            Write-Host "    Clean build" -ForegroundColor Green
        } else {
            Write-Host "    $errCount error(s), $warnCount warning(s)" -ForegroundColor $(if ($errCount -gt 0) { 'Red' } else { 'Yellow' })
        }
    }
}

# ── Step B: Fix errors and warnings with Claude ──

$solutionsWithIssues = $results | Where-Object { $_.Errors.Count -gt 0 -or $_.Warnings.Count -gt 0 }

if ($solutionsWithIssues.Count -gt 0) {
    Write-Host "`n=== FIXING ISSUES WITH CLAUDE ===" -ForegroundColor Yellow

    foreach ($sol in $solutionsWithIssues) {
        $slnxPath = $sol.Solution
        $slnDir = Split-Path $slnxPath -Parent
        $slnName = $sol.SolutionName

        $issueList = ""
        if ($sol.Errors.Count -gt 0) {
            $issueList += "ERRORS:`n"
            foreach ($err in $sol.Errors) { $issueList += "  $err`n" }
            $issueList += "`n"
        }
        if ($sol.Warnings.Count -gt 0) {
            $issueList += "WARNINGS:`n"
            foreach ($warn in $sol.Warnings) { $issueList += "  $warn`n" }
        }

        $originalErrors = $sol.Errors.Count
        $originalWarnings = $sol.Warnings.Count

        for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
            if ($PSCmdlet.ShouldProcess($slnName, "Fix build issues with Claude")) {
                Write-Host "`n  [$($sol.Repo)] $slnName — Claude fix attempt $attempt/$MaxRetries" -ForegroundColor Cyan

                $prompt = "Fix the following dotnet build errors and warnings in this project. After fixing, run ``dotnet build $slnName`` to verify the fix. Here are the issues:`n`n$issueList"
                & claude --dangerously-skip-permissions -p $prompt --cwd $slnDir

                # Re-build to check
                $updated = Build-Solution -SlnxPath $slnxPath

                $issueList = ""
                if ($updated.Errors.Count -gt 0) {
                    $issueList += "ERRORS:`n"
                    foreach ($err in $updated.Errors) { $issueList += "  $err`n" }
                    $issueList += "`n"
                }
                if ($updated.Warnings.Count -gt 0) {
                    $issueList += "WARNINGS:`n"
                    foreach ($warn in $updated.Warnings) { $issueList += "  $warn`n" }
                }

                # Update result in-place
                $sol.Errors = $updated.Errors
                $sol.Warnings = $updated.Warnings
                $sol.Success = $updated.Success

                if ($updated.Errors.Count -eq 0 -and $updated.Warnings.Count -eq 0) {
                    Write-Host "    All issues fixed!" -ForegroundColor Green
                    break
                } else {
                    Write-Host "    $($updated.Errors.Count) error(s), $($updated.Warnings.Count) warning(s) remaining" -ForegroundColor Yellow
                }
            }
        }

        $sol.ErrorsFixed = $originalErrors - $sol.Errors.Count
        $sol.WarningsFixed = $originalWarnings - $sol.Warnings.Count
    }
}

# ── Step C: Final report ──

$reportLines = @()
$reportLines += ""
$reportLines += "=== BUILD AND FIX REPORT ==="
$reportLines += ""

$totalSolutions = $results.Count
$totalErrorsFixed = 0
$totalWarningsFixed = 0
$totalRemaining = 0

$groupedByRepo = $results | Group-Object -Property Repo

foreach ($group in $groupedByRepo) {
    $reportLines += "[Repo: $($group.Name)]"

    foreach ($sol in $group.Group) {
        $errCount = $sol.Errors.Count
        $warnCount = $sol.Warnings.Count
        $errFixed = if ($null -ne $sol.ErrorsFixed) { $sol.ErrorsFixed } else { 0 }
        $warnFixed = if ($null -ne $sol.WarningsFixed) { $sol.WarningsFixed } else { 0 }

        $totalErrorsFixed += $errFixed
        $totalWarningsFixed += $warnFixed
        $totalRemaining += $errCount + $warnCount

        $fixInfo = @()
        if ($errFixed -gt 0) { $fixInfo += "$errFixed error(s) fixed" }
        if ($warnFixed -gt 0) { $fixInfo += "$warnFixed warning(s) fixed" }
        $fixStr = if ($fixInfo.Count -gt 0) { " ($($fixInfo -join ', '))" } else { "" }

        if ($errCount -eq 0 -and $warnCount -eq 0) {
            $icon = [char]0x2705  # ✅
            $reportLines += "  $($sol.SolutionName): $icon Clean$fixStr"
        } elseif ($errCount -gt 0) {
            $icon = [char]0x274C  # ❌
            $reportLines += "  $($sol.SolutionName): $icon $errCount error(s), $warnCount warning(s) remaining$fixStr"
        } else {
            $icon = [char]0x26A0  # ⚠️
            $reportLines += "  $($sol.SolutionName): $icon $warnCount warning(s) remaining$fixStr"
        }
    }

    $reportLines += ""
}

$reportLines += "Total: $totalSolutions solutions, $totalErrorsFixed errors fixed, $totalWarningsFixed warnings fixed, $totalRemaining issues remaining"
$reportLines += ""

$report = $reportLines -join "`n"
Write-Host $report

$report | Out-File -FilePath $reportPath -Encoding utf8
Write-Host "Report saved to $reportPath" -ForegroundColor Green
