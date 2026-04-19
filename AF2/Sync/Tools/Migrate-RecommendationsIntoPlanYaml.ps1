<#
.SYNOPSIS
    One-time migration: moves recommendations from artifacts/recommendations.yaml into plan.yaml.
.DESCRIPTION
    For each plan folder in the given directory:
    1. Reads artifacts/recommendations.yaml
    2. Appends a 'recommendations:' block to plan.yaml
    3. Deletes the artifacts/recommendations.yaml file
    4. Removes the artifacts/ directory if empty
.PARAMETER PlansDir
    Path to the plans directory (default: D:\Plans)
.PARAMETER DryRun
    If set, only prints what would be done without making changes.
#>
param(
    [string]$PlansDir = "D:\Plans",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$planFolders = Get-ChildItem -Path $PlansDir -Directory | Where-Object { $_.Name -match '^\d{5}-' }
$migrated = 0
$skipped = 0
$errors = 0

foreach ($folder in $planFolders) {
    $recPath = Join-Path $folder.FullName "artifacts\recommendations.yaml"
    $planYamlPath = Join-Path $folder.FullName "plan.yaml"

    if (-not (Test-Path $recPath)) {
        $skipped++
        continue
    }

    if (-not (Test-Path $planYamlPath)) {
        Write-Warning "$($folder.Name): plan.yaml missing, skipping"
        $skipped++
        continue
    }

    try {
        $planYaml = Get-Content $planYamlPath -Raw
        if ($planYaml -match '(?m)^recommendations:') {
            Write-Host "$($folder.Name): already has recommendations in plan.yaml, skipping" -ForegroundColor Yellow
            $skipped++
            continue
        }

        $recContent = Get-Content $recPath -Raw
        if ([string]::IsNullOrWhiteSpace($recContent)) {
            if (-not $DryRun) {
                Remove-Item $recPath -Force
                $artifactsDir = Join-Path $folder.FullName "artifacts"
                if ((Test-Path $artifactsDir) -and (Get-ChildItem $artifactsDir | Measure-Object).Count -eq 0) {
                    Remove-Item $artifactsDir -Force
                }
            }
            Write-Host "$($folder.Name): empty recommendations, removed file" -ForegroundColor Gray
            $migrated++
            continue
        }

        # Parse the recommendation entries (list of - title: ... blocks)
        # Re-indent under the recommendations: key
        $lines = $recContent -split "`n"
        $recsBlock = "recommendations:`n"
        foreach ($line in $lines) {
            $trimmed = $line.TrimEnd("`r")
            if ($trimmed -ne "") {
                $recsBlock += "  $trimmed`n"
            }
        }

        # Ensure plan.yaml ends with a newline before appending
        $planYaml = $planYaml.TrimEnd()

        $newPlanYaml = "$planYaml`n$recsBlock"

        if ($DryRun) {
            Write-Host "$($folder.Name): would migrate $(($lines | Where-Object { $_ -match '^\s*-\s+title:' }).Count) recommendation(s)" -ForegroundColor Cyan
        } else {
            Set-Content -Path $planYamlPath -Value $newPlanYaml -NoNewline -Encoding UTF8
            Remove-Item $recPath -Force
            $artifactsDir = Join-Path $folder.FullName "artifacts"
            if ((Test-Path $artifactsDir) -and (Get-ChildItem $artifactsDir | Measure-Object).Count -eq 0) {
                Remove-Item $artifactsDir -Force
            }
            Write-Host "$($folder.Name): migrated" -ForegroundColor Green
        }
        $migrated++
    }
    catch {
        Write-Warning "$($folder.Name): ERROR - $_"
        $errors++
    }
}

Write-Host "`n--- Summary ---"
Write-Host "Migrated: $migrated"
Write-Host "Skipped:  $skipped"
Write-Host "Errors:   $errors"
