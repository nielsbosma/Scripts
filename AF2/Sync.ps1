param(
    [switch]$IvyFramework,
    [switch]$Ivy,
    [switch]$IvyTendril,
    [switch]$Scripts,
    [switch]$NoBuild,
    [switch]$PullOnly
)

. "$PSScriptRoot\.shared\Utils.ps1"

# Map switches to repo paths
$repoMap = @{
    IvyFramework = "D:\Repos\_Ivy\Ivy-Framework"
    Ivy          = "D:\Repos\_Ivy\Ivy"
    IvyTendril   = "D:\Repos\_Ivy\Ivy-Tendril"
    Scripts      = "D:\Repos\_Personal\Scripts"
}

# Determine which repos to sync
$selectedSwitches = @()
if ($IvyFramework) { $selectedSwitches += "IvyFramework" }
if ($Ivy)          { $selectedSwitches += "Ivy" }
if ($IvyTendril)   { $selectedSwitches += "IvyTendril" }
if ($Scripts)      { $selectedSwitches += "Scripts" }

# If none specified, sync all
if ($selectedSwitches.Count -eq 0) {
    $selectedSwitches = $repoMap.Keys
}

$repos = $selectedSwitches | ForEach-Object { $repoMap[$_] }

# Ensure selected repos are on the expected branch
$notOnExpected = @()
foreach ($repo in $repos) {
    if (-not (Test-Path (Join-Path $repo ".git"))) { continue }
    $branch = git -C $repo branch --show-current 2>$null
    $expectedBranch = if ($repo -eq $repoMap["Scripts"]) { "main" } else { "development" }
    if ($branch -ne $expectedBranch) {
        $notOnExpected += "$repo (on '$branch', expected '$expectedBranch')"
    }
}
if ($notOnExpected.Count -gt 0) {
    Write-Host "ERROR: The following repos are not on the expected branch:" -ForegroundColor Red
    foreach ($r in $notOnExpected) { Write-Host "  - $r" -ForegroundColor Red }
    Write-Host "Switch all repos to the correct branch before running Sync." -ForegroundColor Red
    exit 1
}

# Pull-only mode: just git pull on selected repos and exit
if ($PullOnly) {
    foreach ($repo in $repos) {
        $name = Split-Path $repo -Leaf
        Write-Host "Pulling $name..." -ForegroundColor Cyan
        git -C $repo pull
    }
    exit 0
}

$programFolder = GetProgramFolder $PSCommandPath

# Build args: pass repo filter and flags to the agent
$extraArgs = @()
if ($selectedSwitches.Count -lt $repoMap.Count) {
    $extraArgs += "-Repos"
    $extraArgs += ($repos -join ",")
}
if ($NoBuild) { $extraArgs += "-NoBuild" }
$extraArgs += $args

$syncArgs = CollectArgs $extraArgs -Optional

$logFile = GetNextLogFile $programFolder
$syncArgs | Set-Content $logFile
Write-Host "Log file: $logFile"

$promptFile = PrepareFirmware $PSScriptRoot $logFile $programFolder @{ Args = $syncArgs; WorkDir = (Get-Location).Path }

Write-Host "Starting Claude Code..."
Push-Location $programFolder
claude --dangerously-skip-permissions -- (Get-Content $promptFile -Raw)
Pop-Location

Remove-Item $promptFile
