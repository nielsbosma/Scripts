# Pure console folder picker for D:\Repos\_Ivy\
$basePath = "D:\Repos\_Ivy"
$folders = Get-ChildItem -Path $basePath -Directory | Select-Object -ExpandProperty Name

if (-not $folders) {
    Write-Host "No folders found in $basePath" -ForegroundColor Red
    exit
}

$selectedIndex = 0

function DrawMenu {
    Clear-Host
    Write-Host "Select a folder (Use Up/Down arrows, Enter to confirm):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $folders.Count; $i++) {
        if ($i -eq $selectedIndex) {
            Write-Host "> $($folders[$i])" -ForegroundColor Yellow
        } else {
            Write-Host "  $($folders[$i])"
        }
    }
}

# Menu loop
$done = $false
while (-not $done) {
    DrawMenu
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").VirtualKeyCode

    switch ($key) {
        38 { if ($selectedIndex -gt 0) { $selectedIndex-- } }     # Up arrow
        40 { if ($selectedIndex -lt ($folders.Count - 1)) { $selectedIndex++ } } # Down arrow
        13 { $done = $true }                                      # Enter
    }
}

$chosenFolder = $folders[$selectedIndex]
Set-Location -Path (Join-Path $basePath $chosenFolder)
Clear-Host