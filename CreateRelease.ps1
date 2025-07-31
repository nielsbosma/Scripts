# ReleaseServices.ps1
# Script to manage Ivy-Services releases

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Services", "Infra")]
    [string]$Repo = "Services"
)

# Import shared functions
. "$PSScriptRoot\_Shared.ps1"

# Set repository path based on selection
if ($Repo -eq "Services") {
    $repoPath = "D:\Repos\_Ivy\Ivy-Services"
} else {
    $repoPath = "D:\Repos\_Ivy\Ivy-Infrastructure"
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