. "$PSScriptRoot\.shared\Utils.ps1"

$programFolder = GetProgramFolder $PSCommandPath

# Resolve session ID from project's .ivy/session.ldjson
$sessionId = GetLatestSessionId
$args = CollectArgs $args -Optional

# Resolve langfuse data folder
$debugFolder = if ($env:IVY_AGENT_DEBUG_FOLDER) { $env:IVY_AGENT_DEBUG_FOLDER.Trim() } else { $null }
if (-not $debugFolder) {
    Write-Host "Error: IVY_AGENT_DEBUG_FOLDER environment variable is not set." -ForegroundColor Red
    exit 1
}

$langfuseDir = Join-Path (Join-Path $debugFolder $sessionId) "langfuse"

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
    & $ivyAgent langfuse session get $sessionId
    if (-not (Test-Path $langfuseDir)) {
        Write-Host "Error: Download completed but no langfuse data was created." -ForegroundColor Red
        exit 1
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
