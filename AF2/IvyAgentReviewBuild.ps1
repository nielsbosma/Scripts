. "$PSScriptRoot\.shared\Utils.ps1"

$programFolder = GetProgramFolder $PSCommandPath

$args = CollectArgs $args -Optional
$logFile = GetNextLogFile $programFolder
$args | Set-Content $logFile
Write-Host "Log file: $logFile"

$promptFile = PrepareFirmware $PSScriptRoot $logFile @{ Args = $args; WorkDir = (Get-Location).Path }

Write-Host "Starting Agent..."
Push-Location $programFolder
claude --dangerously-skip-permissions -p -- (Get-Content $promptFile -Raw)
Pop-Location

Remove-Item $promptFile
