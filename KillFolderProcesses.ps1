param(
    [Parameter(Position = 0)]
    [string]$FolderPath = (Get-Location).Path,

    [switch]$WhatIf
)

$resolvedPath = (Resolve-Path $FolderPath -ErrorAction Stop).Path

$processes = Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($resolvedPath, [System.StringComparison]::OrdinalIgnoreCase) }

if (-not $processes) {
    Write-Host "No processes found running from: $resolvedPath"
    return
}

if ($WhatIf) {
    Write-Host "Would kill the following processes:"
    $processes | Format-Table Id, Name, Path -AutoSize
    return
}

Write-Host "Killing $($processes.Count) process(es) from: $resolvedPath"
$processes | ForEach-Object {
    Write-Host "  Stopping $($_.Name) (PID $($_.Id))"
    $_ | Stop-Process -Force
}
