#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Creates a new temporary test folder and initializes an Ivy project
.DESCRIPTION
    Creates a new folder in D:\Temp\TestX\ where X is the next available number,
    then navigates to that folder and runs ivy-local init
#>

param(
    [switch]$OpenInExplorer
)

# Ensure D:\Temp exists
$tempRoot = "D:\Temp"
if (-not (Test-Path $tempRoot)) {
    Write-Host "Creating $tempRoot directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
}

# Find the next available TestX number
$existingFolders = Get-ChildItem -Path $tempRoot -Directory -Filter "Test*" | 
    Where-Object { $_.Name -match '^Test(\d+)$' } |
    ForEach-Object { [int]$Matches[1] } |
    Sort-Object

$nextNumber = 1
if ($existingFolders) {
    $nextNumber = ($existingFolders | Measure-Object -Maximum).Maximum + 1
}

# Create the new Test folder
$newFolder = Join-Path $tempRoot "Test$nextNumber"
Write-Host "Creating folder: $newFolder" -ForegroundColor Green
New-Item -ItemType Directory -Path $newFolder -Force | Out-Null

# Navigate to the new folder
Push-Location $newFolder
Write-Host "Changed to directory: $newFolder" -ForegroundColor Cyan

# Run ivy-local init
Write-Host "Initializing Ivy project..." -ForegroundColor Yellow
try {
    ivy-local init
    Write-Host "Ivy project initialized successfully!" -ForegroundColor Green
    Write-Host "Project location: $newFolder" -ForegroundColor Cyan
    
    if ($OpenInExplorer) {
        explorer $newFolder
    }
    
    # Keep the location change
    Write-Host "`nYou are now in: $newFolder" -ForegroundColor Magenta
}
catch {
    Write-Host "Failed to initialize Ivy project: $_" -ForegroundColor Red
    Pop-Location
    exit 1
}