param(
    [switch]$IvyFramework,
    [switch]$IvyAgent,
    [switch]$Ivy,
    [switch]$IvyMcp,
    [switch]$Scripts,
    [switch]$NoBuild,
    [switch]$PullOnly
)

. "$PSScriptRoot\.shared\Utils.ps1"

# Map switches to repo paths
$repoMap = @{
    IvyFramework = "D:\Repos\_Ivy\Ivy-Framework"
    IvyAgent     = "D:\Repos\_Ivy\Ivy-Agent"
    Ivy          = "D:\Repos\_Ivy\Ivy"
    IvyMcp       = "D:\Repos\_Ivy\Ivy-Mcp"
    Scripts      = "D:\Repos\_Personal\Scripts"
}

# Determine which repos to sync
$selectedSwitches = @()
if ($IvyFramework) { $selectedSwitches += "IvyFramework" }
if ($IvyAgent)     { $selectedSwitches += "IvyAgent" }
if ($Ivy)          { $selectedSwitches += "Ivy" }
if ($IvyMcp)       { $selectedSwitches += "IvyMcp" }
if ($Scripts)      { $selectedSwitches += "Scripts" }

# If none specified, sync all
if ($selectedSwitches.Count -eq 0) {
    $selectedSwitches = $repoMap.Keys
}

$repos = $selectedSwitches | ForEach-Object { $repoMap[$_] }

# Ensure selected repos are on main
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
