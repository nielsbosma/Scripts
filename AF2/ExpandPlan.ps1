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

# Move plan to expanding/
$expandingDir = Join-Path (Split-Path $resolved.Path) "expanding"
if (-not (Test-Path $expandingDir)) {
    New-Item -ItemType Directory -Path $expandingDir | Out-Null
}
$expandingPath = Join-Path $expandingDir (Split-Path $resolved.Path -Leaf)
Move-Item -Path $resolved.Path -Destination $expandingPath -Force
Write-Host "Moved to: $expandingPath"

$logFile = GetNextLogFile $programFolder
$expandingPath | Set-Content $logFile
Write-Host "Log file: $logFile"

$promptFile = PrepareFirmware $PSScriptRoot $logFile $programFolder @{ Args = $expandingPath; WorkDir = (Get-Location).Path }

Write-Host "Starting Agent..."
Push-Location $programFolder
claude --dangerously-skip-permissions -- (Get-Content $promptFile -Raw)
Pop-Location

Remove-Item $promptFile
