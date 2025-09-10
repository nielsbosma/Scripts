# CreateRelease.ps1
# Script to create releases for the current git repository
#
# .SYNOPSIS
# Creates a new release for the current git repository
#
# .DESCRIPTION
# This script automatically creates a new release for the current git repository.
# It can either auto-increment the version from the latest tag or use a specified version.
#
# .PARAMETER Version
# Optional. Specifies the version to use for the release. If not provided, the script
# will automatically increment the version number from the latest tag.
#
# .EXAMPLE
# ./CreateRelease.ps1
# Creates a new release with an auto-incremented version number.
#
# .EXAMPLE
# ./CreateRelease.ps1 -Version "1.2.3"
# Creates a new release with the specified version 1.2.3.

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$Version,
    [Parameter(Mandatory = $false)]
    [switch]$Pre
)

# Import shared functions
. "$PSScriptRoot\_Shared.ps1"

# Function to find git repository in current or parent directories
function Find-GitRepository {
    $currentPath = Get-Location
    $originalPath = $currentPath
    
    while ($currentPath) {
        if (Test-Path (Join-Path $currentPath ".git")) {
            return $currentPath
        }
        
        $parent = Split-Path $currentPath -Parent
        if ($parent -eq $currentPath) {
            # We've reached the root
            break
        }
        $currentPath = $parent
    }
    
    return $null
}

# Check for git repository in current or parent directories
$repoPath = Find-GitRepository
if (-not $repoPath) {
    Write-Error "Not in a git repository. No .git folder found in current or parent directories."
    exit 1
}

# Change to git repository root if needed
$currentLocation = Get-Location
if ($repoPath.Path -ne $currentLocation.Path) {
    Write-Host "Found git repository at: $repoPath" -ForegroundColor Yellow
    Write-Host "Changing to repository root..." -ForegroundColor Yellow
    Set-Location $repoPath
}

# Check for Directory.Build.props in repository root
$directoryBuildPropsPath = Join-Path $repoPath "Directory.Build.props"
$versionFromProps = $null

if (Test-Path $directoryBuildPropsPath) {
    Write-Host "Found Directory.Build.props, parsing version..." -ForegroundColor Yellow
    $propsContent = Get-Content -Path $directoryBuildPropsPath -Raw
    if ($propsContent -match '<Version>([^<]+)</Version>') {
        $versionFromProps = $matches[1]
        Write-Host "Version from Directory.Build.props: $versionFromProps" -ForegroundColor Green
    }
}

# Get the latest tag
$tag = Get-LatestTag -RepoPath $repoPath

# Main execution
if ($tag -or $versionFromProps) {
    # Use specified version if provided, otherwise use version from props or calculate next version
    if ($Version) {
        $newVersion = $Version
        Write-Host "Using specified version: $newVersion" -ForegroundColor Green
    } elseif ($versionFromProps) {
        $newVersion = $versionFromProps
        Write-Host "Using version from Directory.Build.props: $newVersion" -ForegroundColor Green
        if ($tag) {
            Write-Host "Current tag version: $tag" -ForegroundColor Cyan
        }
    } elseif ($tag) {
        $newVersion = Get-IncrementedVersion -Tag $tag
        if (-not $newVersion) {
            exit 1
        }
        Write-Host "Current version: $tag" -ForegroundColor Cyan
        Write-Host "Auto-incremented version: $newVersion" -ForegroundColor Green
    } else {
        Write-Error "No version source found (no tags, no Directory.Build.props, and no version specified)"
        exit 1
    }
    
    # Add prerelease suffix if -Pre flag is used
    if ($Pre) {
        # Generate a timestamp suffix for unique prerelease version
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $newVersion = "${newVersion}-pre-${timestamp}"
        Write-Host "Prerelease version with suffix: $newVersion" -ForegroundColor Magenta
    }
    
    # Ask for confirmation
    $releaseType = if ($Pre) { "prerelease" } else { "release" }
    Write-Host "`nDo you want to create a new $releaseType with version $newVersion? (Y/N)" -ForegroundColor Yellow
    $confirmation = Read-Host
    
    if ($confirmation -eq 'Y' -or $confirmation -eq 'y') {
        # Create the release
        $success = New-Release -Version $newVersion -RepoPath $repoPath -Prerelease:$Pre
        
        if (-not $success) {
            Write-Host "Release creation failed" -ForegroundColor Red
        }
    } else {
        Write-Host "Release creation cancelled" -ForegroundColor Yellow
    }
} else {
    Write-Error "No version source found (no tags, no Directory.Build.props, and no version specified)"
    exit 1
}