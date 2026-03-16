<#
.SYNOPSIS
    Installs or uninstalls Windows Explorer context menu entries.

.DESCRIPTION
    Adds a "Run with IvyFeatureTester..." right-click context menu option
    for folders in Windows Explorer. Requires Administrator privileges.

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

# --- Configuration ---
$MenuLabel = "Run with IvyFeatureTester..."
$ScriptPath = "D:\Repos\_Personal\Scripts\AF2\IvyFeatureTester.ps1"
$RegistryKeyName = "IvyFeatureTester"

# Registry paths for both "right-click on folder" and "right-click inside folder background"
$RegistryPaths = @(
    "Registry::HKEY_CLASSES_ROOT\Directory\shell\$RegistryKeyName"
    "Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\$RegistryKeyName"
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
    foreach ($regPath in $RegistryPaths) {
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Recurse -Force
            Write-Host "Removed: $regPath" -ForegroundColor Green
        } else {
            Write-Host "Not found (already removed): $regPath" -ForegroundColor DarkGray
        }
    }
    Write-Host "`nContext menu uninstalled successfully." -ForegroundColor Green
    return
}

# --- Install ---

# Warn if the target script doesn't exist
if (-not (Test-Path $ScriptPath)) {
    Write-Warning "Target script not found at: $ScriptPath"
    Write-Warning "The context menu will be installed but won't work until the script exists at that path."
}

# Command that the context menu will execute
# %V = the folder path clicked in Explorer
$command = "powershell.exe -NoExit -ExecutionPolicy Bypass -Command `"& '$ScriptPath' '%V'`""

foreach ($regPath in $RegistryPaths) {
    # Create the shell key with the menu label
    New-Item -Path $regPath -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name '(Default)' -Value $MenuLabel
    Set-ItemProperty -Path $regPath -Name 'Icon' -Value 'powershell.exe'

    # Create the command subkey
    $commandPath = "$regPath\command"
    New-Item -Path $commandPath -Force | Out-Null
    Set-ItemProperty -Path $commandPath -Name '(Default)' -Value $command

    Write-Host "Installed: $regPath" -ForegroundColor Green
}

Write-Host "`nContext menu installed successfully." -ForegroundColor Green
Write-Host "Right-click on or inside a folder to see '$MenuLabel'." -ForegroundColor Cyan
