. "$PSScriptRoot\.shared\Utils.ps1"

$programFolder = GetProgramFolder $PSCommandPath

# Resolve session ID from project's .ivy/session.ldjson
$sessionId = GetLatestSessionId
$args = CollectArgs $args -Optional

# Resolve langfuse data folder
$workDir = (Get-Location).Path
$langfuseDir = Join-Path $workDir ".ivy" "sessions" $sessionId "langfuse"

# Download langfuse data if not already present
if (-not (Test-Path $langfuseDir)) {
    Write-Host "No langfuse data found locally. Downloading..."
    $ivyAgent = Join-Path $env:USERPROFILE ".dotnet\tools\ivy-agent.exe"
    if (-not (Test-Path $ivyAgent)) {
        # Fallback: try from PATH or build output
        $ivyAgent = (Get-Command ivy-agent -ErrorAction SilentlyContinue)?.Source
    }
    if (-not $ivyAgent) {
        # Last resort: use the build output directly
        $ivyAgent = "D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent.Console\bin\Debug\net9.0\ivy-agent.exe"
    }
    & $ivyAgent langfuse session get $sessionId -d $workDir
    if (-not (Test-Path $langfuseDir)) {
        # Create empty langfuse dir so the agent can still generate session-status report
        Write-Host "Warning: Download completed but no langfuse data was created. Creating empty dir for partial analysis." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $langfuseDir -Force | Out-Null
    }
}

Write-Host "Langfuse data: $langfuseDir"

$logFile = GetNextLogFile $programFolder
$args | Set-Content $logFile
Write-Host "Log file: $logFile"

$workDir = (Get-Location).Path
$promptFile = PrepareFirmware $PSScriptRoot $logFile $programFolder @{
    Args = $args
    WorkDir = $workDir
    SessionId = $sessionId
    LangfuseDir = $langfuseDir
}

Write-Host "Starting Agent..."
Push-Location $programFolder
claude --dangerously-skip-permissions -p -- (Get-Content $promptFile -Raw)
Pop-Location

Remove-Item $promptFile
