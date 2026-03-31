# Closes all virtual desktops except one, merging all windows onto a single desktop.
# Requires: Install-Module VirtualDesktop

Import-Module VirtualDesktop -ErrorAction Stop

$count = Get-DesktopCount
if ($count -le 1) {
    Write-Host "Only one desktop exists, nothing to merge."
    return
}

Write-Host "Merging $count virtual desktops into one..."
while ((Get-DesktopCount) -gt 1) {
    Remove-Desktop (Get-Desktop 1)
}
Write-Host "Done. All windows are now on a single desktop."
