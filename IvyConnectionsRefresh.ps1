$ErrorActionPreference = "Stop"

$IvyRoot = "D:\Repos\_Ivy\Ivy"
$IvyMcpExtractor = "D:\Repos\_Ivy\Ivy-Mcp\src\Ivy.Mcp.Extractor"

# 0. Read version from Directory.Build.props and ensure it's X.Y.Z.W
[xml]$buildProps = Get-Content "$IvyRoot\Directory.Build.props"
$version = $buildProps.Project.PropertyGroup[0].Version

if ($version -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    if ($version -match '^\d+\.\d+\.\d+$') {
        $version = "$version.0"
    } else {
        Write-Error "Version '$version' is not a valid X.Y.Z or X.Y.Z.W format"
        exit 1
    }
}

Write-Host "Version: $version" -ForegroundColor Cyan

# 1. Clear connections cache
$connectionsCache = Join-Path $env:APPDATA "Ivy.Console\connections"
if (Test-Path $connectionsCache) {
    Write-Host "Clearing $connectionsCache..." -ForegroundColor Yellow
    Remove-Item "$connectionsCache\*" -Recurse -Force
} else {
    Write-Host "No connections cache to clear." -ForegroundColor Gray
}

# 2. Pack all connections
$connectionsPath = "$IvyRoot\connections"
$packerPath = "$IvyRoot\connections\.tools\Ivy.Workflows.Connections.Packer"
$outputPath = Join-Path $env:TEMP "ivy-connections-output"

Write-Host "`nPacking connections..." -ForegroundColor Yellow
& "$IvyRoot\connections\.tools\PackAll.ps1" `
    -ConnectionsPath $connectionsPath `
    -Version $version `
    -OutputPath $outputPath `
    -PackerPath $packerPath

if ($LASTEXITCODE -ne 0) {
    Write-Error "PackAll.ps1 failed"
    exit 1
}

$bundlePath = Join-Path $outputPath "Ivy-Agent-Connections-$version.zip"
if (-not (Test-Path $bundlePath)) {
    Write-Error "Expected bundle not found: $bundlePath"
    exit 1
}

Write-Host "Bundle: $bundlePath" -ForegroundColor Green

# 3. Extract and upload connections
Write-Host "`nExtracting connections to blob storage..." -ForegroundColor Yellow
dotnet run --project $IvyMcpExtractor -- extract-connections `
    --source $bundlePath `
    --version $version

if ($LASTEXITCODE -ne 0) {
    Write-Error "extract-connections failed"
    exit 1
}

Write-Host "`nDone!" -ForegroundColor Green
