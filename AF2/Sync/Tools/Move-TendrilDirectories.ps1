# Move-TendrilDirectories.ps1
# Moves Tendril directories and fixes git worktree references

param([switch]$WhatIf)

$sourceBase = "D:\Tendril"
$targetBase = "D:\Repos\_Ivy\Ivy-Framework\src\tendril\Ivy.Tendril.TeamIvyConfig"
$mainRepo = "D:\Repos\_Ivy\Ivy-Tendril"
$directories = @("Inbox", "Plans", "Trash")

Write-Host "Tendril Directory Migration Tool" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Source: $sourceBase" -ForegroundColor Yellow
Write-Host "Target: $targetBase" -ForegroundColor Green
Write-Host ""

if ($WhatIf) {
    Write-Host "[WHATIF MODE - No changes will be made]" -ForegroundColor Magenta
    Write-Host ""
}

# Step 1: Move directories
foreach ($dir in $directories) {
    $source = Join-Path $sourceBase $dir
    $target = Join-Path $targetBase $dir

    if (Test-Path $source) {
        Write-Host "Moving: $dir" -ForegroundColor Cyan
        if (!$WhatIf) {
            Move-Item -Path $source -Destination $target -Force
            Write-Host "  Moved to $target" -ForegroundColor Green
        } else {
            Write-Host "  [WhatIf] Would move to $target" -ForegroundColor Gray
        }
    } else {
        Write-Host "Skipping: $dir (not found)" -ForegroundColor Yellow
    }
}

# Step 2: Fix git worktree references
Write-Host ""
Write-Host "Fixing git worktree references..." -ForegroundColor Cyan

$worktreesDir = Join-Path $mainRepo ".git\worktrees"
if (Test-Path $worktreesDir) {
    $worktreeConfigs = Get-ChildItem -Path $worktreesDir -Directory
    $fixed = 0

    foreach ($wtConfig in $worktreeConfigs) {
        $gitdirFile = Join-Path $wtConfig.FullName "gitdir"

        if (Test-Path $gitdirFile) {
            $oldPath = Get-Content $gitdirFile -Raw
            $oldPath = $oldPath.Trim()

            if ($oldPath -like "*D:/Tendril/*") {
                $newPath = $oldPath.Replace("D:/Tendril/", "D:/Repos/_Ivy/Ivy-Framework/src/tendril/Ivy.Tendril.TeamIvyConfig/")

                if (!$WhatIf) {
                    Set-Content -Path $gitdirFile -Value $newPath -NoNewline
                    $fixed++
                    Write-Host "  Fixed: $($wtConfig.Name)" -ForegroundColor Green
                } else {
                    Write-Host "  [WhatIf] Would fix: $($wtConfig.Name)" -ForegroundColor Gray
                }
            }
        }
    }

    Write-Host ""
    Write-Host "Fixed $fixed worktree references" -ForegroundColor Green
} else {
    Write-Host "No worktrees directory found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Migration complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Verify with: cd '$mainRepo' && git worktree list" -ForegroundColor Cyan
