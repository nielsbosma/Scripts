Get-ChildItem -Path .\ -Directory | ForEach-Object {
    Set-Location -Path $_.FullName
    git pull
    Set-Location -Path ..
}