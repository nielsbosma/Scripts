# Creates a temporary folder under D:\Temp\ and navigates to it

$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$tempPath = "D:\Temp\$timestamp"

New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
Set-Location -Path $tempPath

Write-Host "Created and navigated to: $tempPath"
