param(
    [string]$Prompt,
    [string]$WorkingDirectory
)

$existingServer = Get-Process -Name "Ivy.Agent.Server" -ErrorAction SilentlyContinue
if ($existingServer) {
    Write-Host "Stopping existing Ivy.Agent.Server..."
    $existingServer | Stop-Process -Force
}

dotnet build "D:\Repos\_Ivy\Ivy\Ivy.Console\Ivy.Console.csproj"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed. Exiting."
    exit 1
}

Write-Host "Starting Ivy.Agent.Server in background..."
$serverProcess = Start-Process dotnet -ArgumentList "run", "--project", "D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent.Server\Ivy.Agent.Server.csproj" -WindowStyle Minimized -PassThru

# Wait for the server to start
Write-Host "Waiting for Ivy.Agent.Server to start..."
while ($true) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:5122/health" -UseBasicParsing -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "Ivy.Agent.Server is up and running."
            break
        }
    } catch {
        Write-Host "Waiting for Ivy.Agent.Server to be ready..."
        Start-Sleep -Seconds 1
    }
}

if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
    $targetDir = Join-Path "D:\Temp" ([System.Guid]::NewGuid().ToString()) "Foo.Bar"
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
} elseif ($WorkingDirectory -eq ".") {
    $targetDir = Get-Location
} else {
    $targetDir = Resolve-Path $WorkingDirectory
}

Set-Location $targetDir

$args = @("agent", "--staging", "--debug-agent-server", "http://localhost:5122", "--log-verbose", "--local-source")

if (-not [string]::IsNullOrWhiteSpace($Prompt)) {
    $args += "-p"
    $args += $Prompt
}

ivy-local @args

Write-Host "Stopping Ivy.Agent.Server..."
Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
