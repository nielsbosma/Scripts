. "$PSScriptRoot\.shared\Utils.ps1"

$programFolder = GetProgramFolder $PSCommandPath

$args = CollectArgs $args

$logFile = GetNextLogFile $programFolder
$args | Set-Content $logFile
Write-Host "Log file: $logFile"

$promptFile = PrepareFirmware $PSScriptRoot $logFile @{ Args = $args; WorkDir = (Get-Location).Path }

Write-Host "Starting Claude Code..."
Push-Location $programFolder
claude --dangerously-skip-permissions -- (Get-Content $promptFile -Raw)
Pop-Location

Remove-Item $promptFile
