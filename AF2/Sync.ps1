. "$PSScriptRoot\.shared\Utils.ps1"

# Ensure all repos are on main before syncing
$reposFile = Join-Path $PSScriptRoot ".shared\Repos.md"
$repos = Get-Content $reposFile | Where-Object { $_.Trim() -ne "" }
$notOnMain = @()
foreach ($repo in $repos) {
    if (-not (Test-Path (Join-Path $repo ".git"))) { continue }
    $branch = git -C $repo branch --show-current 2>$null
    if ($branch -ne "main") {
        $notOnMain += "$repo (on '$branch')"
    }
}
if ($notOnMain.Count -gt 0) {
    Write-Host "ERROR: The following repos are not on main:" -ForegroundColor Red
    foreach ($r in $notOnMain) { Write-Host "  - $r" -ForegroundColor Red }
    Write-Host "Switch all repos to main before running Sync." -ForegroundColor Red
    exit 1
}

$programFolder = GetProgramFolder $PSCommandPath

$args = CollectArgs $args -Optional

$logFile = GetNextLogFile $programFolder
$args | Set-Content $logFile
Write-Host "Log file: $logFile"

$promptFile = PrepareFirmware $PSScriptRoot $logFile $programFolder @{ Args = $args; WorkDir = (Get-Location).Path }

Write-Host "Starting Claude Code..."
Push-Location $programFolder
claude --dangerously-skip-permissions -- (Get-Content $promptFile -Raw)
Pop-Location

Remove-Item $promptFile
    