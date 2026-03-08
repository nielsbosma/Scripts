$folders = @('completed', 'failed', 'history', 'logs', 'prompts')
$root = 'D:\Repos\_Ivy\.plans'

foreach ($folder in $folders) {
    $path = Join-Path $root $folder
    if (Test-Path $path) {
        Get-ChildItem -Path $path -File | Remove-Item -Force
        Write-Host "Cleaned $folder"
    }
}
