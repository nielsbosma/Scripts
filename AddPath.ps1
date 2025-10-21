param(
    [Parameter(Mandatory=$true)]
    [string]$path
)

# Get current user PATH
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathEntries = $currentPath -split ';' | Where-Object { $_ -ne '' }

# Normalize the new path
$normalizedNewPath = $path.TrimEnd('\')

# Check if path already exists
$alreadyExists = $pathEntries | Where-Object {
    $_.TrimEnd('\') -eq $normalizedNewPath
}

if ($alreadyExists) {
    Write-Host "Path already exists in user PATH:" -ForegroundColor Yellow
    Write-Host $normalizedNewPath -ForegroundColor Yellow
    exit 0
}

# Display all paths with new one highlighted
Write-Host "`nCurrent PATH entries with new addition:" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

foreach ($entry in $pathEntries) {
    Write-Host $entry
}

Write-Host $normalizedNewPath -ForegroundColor Green -BackgroundColor DarkGray

# Ask to persist
Write-Host "`nPersist? (y/n): " -NoNewline -ForegroundColor Yellow
$response = Read-Host

if ($response -eq 'y' -or $response -eq 'Y') {
    # Safely append new path (handle empty or trailing semicolon cases)
    $newPath = if ($currentPath) {
        $currentPath.TrimEnd(';') + ';' + $normalizedNewPath
    } else {
        $normalizedNewPath
    }

    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")

    # Reload PATH in current session (safely combine machine and user paths)
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")

    $combinedPaths = @($machinePath, $userPath) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd(';') }
    $env:Path = $combinedPaths -join ';'

    Write-Host "Path added successfully!" -ForegroundColor Green
    Write-Host "Current terminal session reloaded with new PATH." -ForegroundColor Green
} else {
    Write-Host "Operation cancelled." -ForegroundColor Red
}
