. "$PSScriptRoot\.shared\Utils.ps1"

$programFolder = GetProgramFolder $PSCommandPath

$args = CollectArgs $args -Optional

$logFile = GetNextLogFile $programFolder
$args | Set-Content $logFile
Write-Host "Log file: $logFile"

$sessionId = [guid]::NewGuid().ToString()

$promptFile = PrepareFirmware $PSScriptRoot $logFile $programFolder @{ Args = $args; WorkDir = "D:\Repos\_Ivy\.plans"; ClaudeSessionId = $sessionId }

Write-Host "Starting Agent..."
Push-Location $programFolder
claude --dangerously-skip-permissions --session-id $sessionId -- (Get-Content $promptFile -Raw)
Pop-Location

Remove-Item $promptFile
