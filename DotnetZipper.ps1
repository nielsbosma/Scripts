param(
    [Parameter(Mandatory=$true)]
    [string]$TargetFolder
)

# Resolve to absolute path
$TargetFolder = Resolve-Path $TargetFolder -ErrorAction Stop

# Get the folder name for the zip file
$folderName = Split-Path $TargetFolder -Leaf
$zipFileName = "$folderName.zip"
$zipPath = Join-Path $TargetFolder $zipFileName

# Remove existing zip if it exists
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
    Write-Host "Removed existing zip: $zipPath"
}

# Create a temporary staging directory
$tempDir = Join-Path $env:TEMP "DotnetZipper_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    Write-Host "Copying files to staging directory..."

    # Copy all files except excluded patterns
    Get-ChildItem -Path $TargetFolder -Recurse -File | Where-Object {
        $relativePath = $_.FullName.Substring($TargetFolder.Length)

        # Exclude patterns
        $exclude = $relativePath -match '[\\/]\.git[\\/]' -or
                   $relativePath -match '[\\/]bin[\\/]' -or
                   $relativePath -match '[\\/]obj[\\/]' -or
                   $relativePath -match '[\\/]node_modules[\\/]' -or
                   $_.Name -eq $zipFileName

        -not $exclude
    } | ForEach-Object {
        $relativePath = $_.FullName.Substring($TargetFolder.Length + 1)
        $destPath = Join-Path $tempDir $relativePath
        $destDir = Split-Path $destPath -Parent

        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        Copy-Item $_.FullName -Destination $destPath -Force
    }

    Write-Host "Creating zip archive: $zipPath"

    # Create zip from staging directory
    Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath -Force

    Write-Host "Successfully created: $zipPath"

} finally {
    # Cleanup staging directory
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
}
