# Create-TendrilSymlinks-Complete.ps1
# Run this script as Administrator to create all Tendril symlinks
# Real files are in Ivy-Framework, symlinks in D:\Tendril point to them

$sourceDir = "D:\Repos\_Ivy\Ivy-Framework\src\tendril\Ivy.Tendril.TeamIvyConfig"
$tendrilDir = "D:\Tendril"

Write-Host "Creating Tendril Symlinks" -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan
Write-Host ""

# Create symlinks for all items
$items = @(
    @{Name=".hooks"; Type="Directory"},
    @{Name=".promptware"; Type="Directory"},
    @{Name="config.yaml"; Type="File"},
    @{Name="Inbox"; Type="Directory"},
    @{Name="Plans"; Type="Directory"},
    @{Name="Trash"; Type="Directory"}
)

foreach ($item in $items) {
    $source = Join-Path $sourceDir $item.Name
    $target = Join-Path $tendrilDir $item.Name

    if (Test-Path $source) {
        Write-Host "Creating symlink: $($item.Name)" -ForegroundColor Cyan

        if ($item.Type -eq "Directory") {
            New-Item -ItemType SymbolicLink -Path $target -Target $source -Force | Out-Null
        } else {
            New-Item -ItemType SymbolicLink -Path $target -Target $source -Force | Out-Null
        }

        Write-Host "  D:\Tendril\$($item.Name) -> $source" -ForegroundColor Green
    } else {
        Write-Host "Skipping: $($item.Name) (source not found)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Symlinks created successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Verify with: Get-Item D:\Tendril\* | Select-Object Name, Target" -ForegroundColor Cyan
