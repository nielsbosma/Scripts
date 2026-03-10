. "$PSScriptRoot\.shared\Utils.ps1"

$programFolder = GetProgramFolder $PSCommandPath

$args = CollectArgs $args -Optional

$logFile = GetNextLogFile $programFolder
$args | Set-Content $logFile
Write-Host "Log file: $logFile"

$firmware = PrepareFirmware $PSScriptRoot $args $logFile

Write-Host "Starting Claude Code..."
Push-Location $programFolder
claude --dangerously-skip-permissions -p $firmware
Pop-Location
