. "$PSScriptRoot\.shared\Utils.ps1"

$programFolder = GetProgramFolder $PSCommandPath

$args = CollectArgs $args
# Args are REQUIRED here — must describe the feature to test

$logFile = GetNextLogFile $programFolder
$args | Set-Content $logFile
Write-Host "Log file: $logFile"

$promptFile = PrepareFirmware $PSScriptRoot $logFile @{ Args = $args; WorkDir = (Get-Location).Path }

Write-Host "Starting Agent..."
Push-Location $programFolder
$output = claude --dangerously-skip-permissions -p -- (Get-Content $promptFile -Raw) 2>&1
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    "`n## Failed`n`nClaude exited with code $exitCode`n`n$output" | Add-Content $logFile
    Write-Host "Claude failed with exit code $exitCode" -ForegroundColor Red
}
Pop-Location

Remove-Item $promptFile
