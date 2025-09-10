<#
.SYNOPSIS
    Deletes a NUL file in the current directory using the special \\?\ prefix with admin elevation.

.DESCRIPTION
    This script deletes files named "NUL" which cannot be deleted normally in Windows.
    It uses the \\?\ prefix to bypass normal Win32 path parsing and requires admin privileges.
    Automatically finds and deletes the NUL file in the current directory.

.EXAMPLE
    .\DeleteNul.ps1
    Deletes the NUL file in the current directory with admin elevation.

.LINK
    https://superuser.com/questions/282194/how-do-i-remove-a-file-named-nul-on-windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TargetDirectory
)

# If TargetDirectory is not provided, use current directory
if (-not $TargetDirectory) {
    $currentDir = (Get-Location).Path
} else {
    $currentDir = $TargetDirectory
}

$fullPath = Join-Path -Path $currentDir -ChildPath "nul"

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Elevating to administrator privileges..." -ForegroundColor Yellow
    Write-Host "Target directory: $currentDir" -ForegroundColor Yellow
    
    # Restart the script with admin privileges, passing the current directory
    $scriptPath = $MyInvocation.MyCommand.Path
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -TargetDirectory `"$currentDir`""
    
    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs -Wait
    }
    catch {
        Write-Error "Failed to elevate to administrator: $_"
        exit 1
    }
    
    # Exit the current non-elevated instance
    exit
}

Write-Host "Running with administrator privileges" -ForegroundColor Green

# Construct the special path with \\?\ prefix
$specialPath = "\\?\$fullPath"

Write-Host "Current directory: $currentDir" -ForegroundColor Cyan
Write-Host "Attempting to delete NUL file at: $fullPath" -ForegroundColor Cyan
Write-Host "Using special path: $specialPath" -ForegroundColor Cyan

try {
    # Use cmd.exe to delete the file with the special path
    $result = & cmd.exe /c "del `"$specialPath`"" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully deleted NUL file: $fullPath" -ForegroundColor Green
    }
    else {
        Write-Error "Failed to delete file. Output: $result"
        exit 1
    }
}
catch {
    Write-Error "Error deleting NUL file: $_"
    exit 1
}

# Since Test-Path has issues with NUL files, check using cmd dir
$checkResult = & cmd.exe /c "dir /b `"$fullPath`"" 2>&1
if ($checkResult -match "File Not Found" -or $checkResult -match "cannot find") {
    Write-Host "Deletion verified - file no longer exists" -ForegroundColor Green
}
else {
    Write-Warning "Unable to verify deletion - NUL files may not appear in normal listings"
}