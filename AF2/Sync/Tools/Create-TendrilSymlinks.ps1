# Create-TendrilSymlinks.ps1
# Run this script as Administrator to create symlinks
# Real files are in Ivy-Framework, symlinks in D:\Tendril point to them

$sourceDir = "D:\Repos\_Ivy\Ivy-Framework\src\tendril\Ivy.Tendril.TeamIvyConfig"
$tendrilDir = "D:\Tendril"

# Create directory symlinks in D:\Tendril
New-Item -ItemType SymbolicLink -Path "$tendrilDir\.hooks" -Target "$sourceDir\.hooks" -Force
New-Item -ItemType SymbolicLink -Path "$tendrilDir\.promptware" -Target "$sourceDir\.promptware" -Force

# Create file symlink in D:\Tendril
New-Item -ItemType SymbolicLink -Path "$tendrilDir\config.yaml" -Target "$sourceDir\config.yaml" -Force

Write-Host "Symlinks created successfully in D:\Tendril!" -ForegroundColor Green
Write-Host "  D:\Tendril\.hooks -> $sourceDir\.hooks"
Write-Host "  D:\Tendril\.promptware -> $sourceDir\.promptware"
Write-Host "  D:\Tendril\config.yaml -> $sourceDir\config.yaml"
