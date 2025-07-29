# OpenServices.ps1
# Opens the GitHub repository connected to D:\Repos\_Ivy\Ivy-Services

$repoPath = "D:\Repos\_Ivy\Ivy-Services"

# Change to the repository directory
Set-Location -Path $repoPath

# Open the repository in the browser using GitHub CLI
gh repo view --web