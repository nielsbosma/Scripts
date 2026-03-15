param(
    [Parameter(Mandatory=$true)]
    [string]$PlanPath
)

. "$PSScriptRoot\.shared\Utils.ps1"

$programFolder = GetProgramFolder $PSCommandPath

# Validate: must be an existing file
$resolved = Resolve-Path -Path $PlanPath -ErrorAction SilentlyContinue
if (-not $resolved) {
    Write-Host "File not found: $PlanPath" -ForegroundColor Red
    exit 1
}

# Validate: must contain at least one >> comment
$content = Get-Content $resolved.Path -Raw
if ($content -notmatch '(?m)^\s*>>') {
    Write-Host "No >> comments found in: $($resolved.Path)" -ForegroundColor Red
    exit 1
}

# Move plan to updating/
$updatingDir = Join-Path (Split-Path $resolved.Path) "updating"
if (-not (Test-Path $updatingDir)) {
    New-Item -ItemType Directory -Path $updatingDir | Out-Null
}
$updatingPath = Join-Path $updatingDir (Split-Path $resolved.Path -Leaf)
Move-Item -Path $resolved.Path -Destination $updatingPath -Force
Write-Host "Moved to: $updatingPath"

$logFile = GetNextLogFile $programFolder
$updatingPath | Set-Content $logFile
Write-Host "Log file: $logFile"

$promptFile = PrepareFirmware $PSScriptRoot $logFile $programFolder @{ Args = $updatingPath; WorkDir = (Get-Location).Path }

Write-Host "Starting Agent..."
Push-Location $programFolder
claude --dangerously-skip-permissions -- (Get-Content $promptFile -Raw)
Pop-Location

Remove-Item $promptFile
