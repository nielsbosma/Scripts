# CreateRelease.ps1
# Script to create releases for the current git repository

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

# Get the latest tag
$tag = Get-LatestTag -RepoPath $repoPath

# Main execution
if ($tag) {
    $newVersion = Get-IncrementedVersion -Tag $tag
    if ($newVersion) {
        Write-Host "Current version: $tag" -ForegroundColor Cyan
        Write-Host "Next version: $newVersion" -ForegroundColor Green
        
        # Ask for confirmation
        Write-Host "`nDo you want to create a new release with version $newVersion? (Y/N)" -ForegroundColor Yellow
        $confirmation = Read-Host
        
        if ($confirmation -eq 'Y' -or $confirmation -eq 'y') {
            # Create the release
            $success = New-Release -Version $newVersion -RepoPath $repoPath
            
            if (-not $success) {
                Write-Host "Release creation failed" -ForegroundColor Red
            }
        } else {
            Write-Host "Release creation cancelled" -ForegroundColor Yellow
        }
    }
}