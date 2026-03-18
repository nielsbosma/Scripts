#Requires -Version 7.0
param(
    [string]$Prompt,
    [string]$WorkingDirectory,
    [switch]$NoBuild,
    [switch]$NonInteractive,
    [switch]$Debug
)

if (-not $NoBuild) {
    dotnet build "D:\Repos\_Ivy\Ivy\Ivy.Console\Ivy.Console.csproj"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed. Exiting."
        exit 1
    }
}

# Find an available port starting from 5122
$port = 5122
while ($true) {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
    try {
        $listener.Start()
        $listener.Stop()
        break
    } catch {
        Write-Host "Port $port is in use, trying next..."
        $port++
    }
}

Write-Host "Starting Ivy.Agent.Server on port $port..."
$serverProcess = Start-Process dotnet -ArgumentList "run", "--project", "D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent.Server\Ivy.Agent.Server.csproj", "--urls", "http://localhost:$port" -WindowStyle Minimized -PassThru

# Wait for the server to start
Write-Host "Waiting for Ivy.Agent.Server to start..."
while ($true) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$port/health" -UseBasicParsing -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "Ivy.Agent.Server is up and running on port $port."
            break
        }
    } catch {
        Write-Host "Waiting for Ivy.Agent.Server to be ready..."
        Start-Sleep -Seconds 1
    }
}

. "$PSScriptRoot\_Shared.ps1"

if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
    $namespace = New-TempNamespace -Prompt $Prompt
    if (-not $namespace) { exit 1 }
    $dateFolder = Get-Date -Format "yyyy-MM-dd"
    $targetDir = Join-Path "D:\Temp\IvyAgentRun" $dateFolder $namespace
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
} elseif ($WorkingDirectory -eq ".") {
    $targetDir = Get-Location
} else {
    $targetDir = Resolve-Path $WorkingDirectory
}

Set-Location $targetDir

if (-not $env:IVY_AGENT_DEBUG_FOLDER) {
    Write-Host "WARNING: IVY_AGENT_DEBUG_FOLDER is not set. --log-output and --log-verbose require it."
    Write-Host "Set it with: `$env:IVY_AGENT_DEBUG_FOLDER = 'D:\Temp\ivy-agent'"
}

$args = @("code", "--staging", "--debug-agent-server", "http://localhost:$port", "--log-verbose", "--local-source", "--exit-on-complete")

if (-not [string]::IsNullOrWhiteSpace($Prompt)) {
    $args += "-p"
    $args += $Prompt
}

if ($NonInteractive) {
    $args += "--non-interactive"
}

Write-Host "Running: ivy-local $($args -join ' ')"
ivy-local @args
$exitCode = $LASTEXITCODE
Write-Host "ivy-local exited with code: $exitCode"

if ($Debug) {
    pwsh -ExecutionPolicy Bypass -File "$PSScriptRoot\AF2\IvyAgentDebug.ps1"
}

Write-Host "Stopping Ivy.Agent.Server..."
Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
