<#
.SYNOPSIS
    Installs or uninstalls Windows Explorer context menu entries.

.DESCRIPTION
    Adds right-click context menu options:
    - "Run with IvyFeatureTester..." for folders
    - "Test with IvyFeatureTester..." for .md files
    Requires Administrator privileges.

.PARAMETER Uninstall
    Remove the context menu entries instead of installing them.

.EXAMPLE
    # Install (run as Administrator)
    .\InstallWindowsContextMenus.ps1

.EXAMPLE
    # Uninstall (run as Administrator)
    .\InstallWindowsContextMenus.ps1 -Uninstall
#>

param(
    [switch]$Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Context Menu Definitions ---
$ContextMenus = @(
    @{
        Label        = "Run with IvyFeatureTester..."
        ScriptPath   = "D:\Repos\_Personal\Scripts\AF2\IvyFeatureTester.ps1"
        RegistryPaths = @(
            "Registry::HKEY_CLASSES_ROOT\Directory\shell\IvyFeatureTester"
            "Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\IvyFeatureTester"
        )
        # %V = the folder path clicked in Explorer
        CommandTemplate = "powershell.exe -NoExit -ExecutionPolicy Bypass -Command `"& '{0}' '%V'`""
    }
    @{
        Label        = "Test with IvyFeatureTester..."
        ScriptPath   = "D:\Repos\_Personal\Scripts\AF2\IvyFeatureTester.ps1"
        RegistryPaths = @(
            "Registry::HKEY_CLASSES_ROOT\SystemFileAssociations\.md\shell\IvyFeatureTester"
        )
        # %1 = the full file path
        CommandTemplate = "powershell.exe -NoExit -ExecutionPolicy Bypass -Command `"& '{0}' '%1'`""
    }
)

# --- Elevation Check ---
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Host "This script requires Administrator privileges. Relaunching elevated..." -ForegroundColor Yellow
    $arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Uninstall) { $arguments += " -Uninstall" }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments
    exit
}

# --- Uninstall ---
if ($Uninstall) {
    foreach ($menu in $ContextMenus) {
        foreach ($regPath in $menu.RegistryPaths) {
            if (Test-Path $regPath) {
                Remove-Item -Path $regPath -Recurse -Force
                Write-Host "Removed: $regPath" -ForegroundColor Green
            } else {
                Write-Host "Not found (already removed): $regPath" -ForegroundColor DarkGray
            }
        }
    }
    Write-Host "`nAll context menus uninstalled successfully." -ForegroundColor Green
    return
}

# --- Install ---
foreach ($menu in $ContextMenus) {
    # Warn if the target script doesn't exist
    if (-not (Test-Path $menu.ScriptPath)) {
        Write-Warning "Target script not found at: $($menu.ScriptPath)"
        Write-Warning "The context menu will be installed but won't work until the script exists at that path."
    }

    $command = $menu.CommandTemplate -f $menu.ScriptPath

    foreach ($regPath in $menu.RegistryPaths) {
        # Create the shell key with the menu label
        New-Item -Path $regPath -Force | Out-Null
        Set-ItemProperty -Path $regPath -Name '(Default)' -Value $menu.Label
        Set-ItemProperty -Path $regPath -Name 'Icon' -Value 'powershell.exe'

        # Create the command subkey
        $commandPath = "$regPath\command"
        New-Item -Path $commandPath -Force | Out-Null
        Set-ItemProperty -Path $commandPath -Name '(Default)' -Value $command

        Write-Host "Installed: $regPath" -ForegroundColor Green
    }
}

Write-Host "`nAll context menus installed successfully." -ForegroundColor Green
Write-Host "- Right-click on or inside a folder for 'Run with IvyFeatureTester...'" -ForegroundColor Cyan
Write-Host "- Right-click on a .md file for 'Test with IvyFeatureTester...'" -ForegroundColor Cyan
