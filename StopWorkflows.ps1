# StopServicesWorkflows.ps1
# Lists all running GitHub Actions workflows for the Ivy-Services repository

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Services", "Infra")]
    [string]$Repo = "Services"
)

# Set repository path based on selection
if ($Repo -eq "Services") {
    $RepoPath = "D:\Repos\_Ivy\Ivy-Services"
} else {
    $RepoPath = "D:\Repos\_Ivy\Ivy-Infrastructure"
}

# Change to the repository directory
Push-Location $RepoPath

try {
    # Get repository information
    $remoteUrl = git config --get remote.origin.url
    if ($remoteUrl -match "github\.com[:/](.+?)/(.+?)(\.git)?$") {
        $owner = $Matches[1]
        $repoName = $Matches[2]
        Write-Host "Repository: $owner/$repoName" -ForegroundColor Cyan
    } else {
        Write-Error "Could not parse GitHub repository information from remote URL"
        exit 1
    }

    # List running workflows
    Write-Host "`nFetching running workflows..." -ForegroundColor Yellow
    $runningWorkflows = gh run list --repo "$owner/$repoName" --status in_progress --json databaseId,displayTitle,workflowName,createdAt,url

    if ($runningWorkflows) {
        $workflows = $runningWorkflows | ConvertFrom-Json
        
        if ($workflows.Count -eq 0) {
            Write-Host "No running workflows found." -ForegroundColor Green
        } else {
            Write-Host "`nFound $($workflows.Count) running workflow(s):" -ForegroundColor Green
            
            foreach ($workflow in $workflows) {
                Write-Host "`n----------------------------------------" -ForegroundColor DarkGray
                Write-Host "Workflow: $($workflow.workflowName)" -ForegroundColor White
                Write-Host "Title: $($workflow.displayTitle)" -ForegroundColor White
                Write-Host "ID: $($workflow.databaseId)" -ForegroundColor Gray
                Write-Host "Started: $($workflow.createdAt)" -ForegroundColor Gray
                Write-Host "URL: $($workflow.url)" -ForegroundColor Blue
            }
            
            Write-Host "`n----------------------------------------" -ForegroundColor DarkGray
            Write-Host "`nTo cancel a workflow, use:" -ForegroundColor Yellow
            Write-Host "gh run cancel <ID> --repo $owner/$repoName" -ForegroundColor Cyan
            
            # Optional: Ask if user wants to cancel all running workflows
            $response = Read-Host "`nDo you want to cancel all running workflows? (y/N)"
            if ($response -eq 'y' -or $response -eq 'Y') {
                foreach ($workflow in $workflows) {
                    Write-Host "Cancelling workflow $($workflow.databaseId)..." -ForegroundColor Yellow
                    gh run cancel $workflow.databaseId --repo "$owner/$repoName"
                }
                Write-Host "All workflows cancelled." -ForegroundColor Green
            }
        }
    } else {
        Write-Host "No running workflows found." -ForegroundColor Green
    }
} catch {
    Write-Error "An error occurred: $_"
} finally {
    Pop-Location
}