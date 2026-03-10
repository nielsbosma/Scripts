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

$logFile = GetNextLogFile $programFolder
$resolved.Path | Set-Content $logFile
Write-Host "Log file: $logFile"

$promptFile = PrepareFirmware $PSScriptRoot $resolved.Path $logFile -WorkDir (Get-Location).Path

Write-Host "Starting Claude Code..."
Push-Location $programFolder
claude --dangerously-skip-permissions -- (Get-Content $promptFile -Raw)
Pop-Location

Remove-Item $promptFile
