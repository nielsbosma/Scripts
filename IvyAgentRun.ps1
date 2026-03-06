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
    $targetDir = Join-Path "D:\Temp\IvyAgentRun" $namespace
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
} elseif ($WorkingDirectory -eq ".") {
    $targetDir = Get-Location
} else {
    $targetDir = Resolve-Path $WorkingDirectory
}

Set-Location $targetDir

$args = @("agent", "--staging", "--debug-agent-server", "http://localhost:$port", "--log-verbose", "--local-source", "--log-output")

if (-not [string]::IsNullOrWhiteSpace($Prompt)) {
    $args += "-p"
    $args += $Prompt
}

if ($NonInteractive) {
    $args += "--non-interactive"
}

ivy-local @args

if ($Debug) {
    & "$PSScriptRoot\IvyAgentDebug.ps1" -Prompt "Analyze the session for issues"
}

Write-Host "Stopping Ivy.Agent.Server..."
Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
