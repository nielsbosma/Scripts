param(
    [string]$Source,
    [string]$Destination
)

$excludeDirs = @('.ivy', 'obj', 'bin', '.vs')

if (Test-Path $Destination) {
    Remove-Item -Recurse -Force $Destination
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null

Get-ChildItem -Path $Source -Recurse -File | Where-Object {
    $path = $_.FullName
    $exclude = $false
    foreach ($dir in $excludeDirs) {
        if ($path -match "\\$dir\\") {
            $exclude = $true
            break
        }
    }
    -not $exclude
} | ForEach-Object {
    $rel = $_.FullName.Substring($Source.Length)
    $target = Join-Path $Destination $rel
    $dir = Split-Path $target
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Copy-Item $_.FullName $target -Force
}

Write-Host "Copied project from $Source to $Destination"
