. "$PSScriptRoot\.shared\Utils.ps1"

$programFolder = GetProgramFolder $PSCommandPath

$args = CollectArgs $args

$logFile = GetNextLogFile $programFolder
$args | Set-Content $logFile
Write-Host "Log file: $logFile"

$sessionId = [guid]::NewGuid().ToString()

$promptFile = PrepareFirmware $PSScriptRoot $logFile @{ Args = $args; WorkDir = (Get-Location).Path; SessionId = $sessionId }

Write-Host "Starting Claude Code..."
Push-Location $programFolder
claude --dangerously-skip-permissions --session-id $sessionId --allowedTools "Read,Glob,Grep,Write,Agent,Bash,WebFetch,WebSearch" -- (Get-Content $promptFile -Raw)
Pop-Location

Remove-Item $promptFile
