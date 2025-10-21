# Get the current directory's absolute path and copy it to the clipboard
$currentPath = (Get-Location).Path
Set-Clipboard -Value $currentPath
Write-Host "Copied to clipboard: $currentPath"
