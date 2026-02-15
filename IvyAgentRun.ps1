param(
    [string]$Prompt,
    [string]$WorkingDirectory
)

$existingServer = Get-Process -Name "Ivy.Agent.Server" -ErrorAction SilentlyContinue
if ($existingServer) {
    Write-Host "Stopping existing Ivy.Agent.Server..."
    $existingServer | Stop-Process -Force
}

Write-Host "Starting Ivy.Agent.Server in background..."
$serverProcess = Start-Process dotnet -ArgumentList "run", "--project", "D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent.Server\Ivy.Agent.Server.csproj" -WindowStyle Minimized -PassThru

dotnet build "D:\Repos\_Ivy\Ivy\Ivy.Console\Ivy.Console.csproj"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed. Exiting."
    exit 1
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

$args = @("agent", "--staging", "--debug-agent-server", "http://localhost:5122", "--log-verbose")

if (-not [string]::IsNullOrWhiteSpace($Prompt)) {
    $args += "-p"
    $args += $Prompt
}

ivy-local @args

Write-Host "Stopping Ivy.Agent.Server..."
Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
