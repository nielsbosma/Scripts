# CreatePullRequest.ps1
# Creates a pull request from unpushed commits using AI-generated branch names

param(
    [string]$BranchName = "",
    [switch]$Approve,
    [switch]$Open,
    [string]$Reviewer = ""
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
$gitRoot = Find-GitRepository
if (-not $gitRoot) {
    Write-Error "Not in a git repository. No .git folder found in current or parent directories."
    exit 1
}

# Change to git repository root if needed
$currentLocation = Get-Location
if ($gitRoot.Path -ne $currentLocation.Path) {
    Write-Host "Found git repository at: $gitRoot" -ForegroundColor Yellow
    Write-Host "Changing to repository root..." -ForegroundColor Yellow
    Set-Location $gitRoot
}

# Check that we are in a repo folder
$gitRemote = git remote -v 2>$null
if (-not $gitRemote) {
    Write-Error "No remote repository found. Please ensure your repository has a remote configured."
    exit 1
}

# Check that there's no uncommitted changes if so fail
$gitStatus = git status --porcelain
if ($gitStatus) {
    Write-Error "You have uncommitted changes. Please commit or stash them before creating a pull request."
    Write-Host "`nUncommitted changes:" -ForegroundColor Yellow
    git status --short
    exit 1
}

# Check that there are at least 1 commit that hasn't been pushed
$currentBranch = git rev-parse --abbrev-ref HEAD
$unpushedCommits = git log origin/$currentBranch..HEAD --oneline 2>$null

if (-not $unpushedCommits) {
    Write-Error "No unpushed commits found on branch '$currentBranch'. Nothing to create a pull request for."
    exit 1
}

Write-Host "Found $($unpushedCommits.Count) unpushed commit(s):" -ForegroundColor Green
$unpushedCommits | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }

# Get the commit messages of all commits that haven't been pushed and join into a single string
$commitMessages = git log origin/$currentBranch..HEAD --pretty=format:"%s" | Out-String

# Get the full diff for all unpushed commits
$fullDiff = git diff origin/$currentBranch..HEAD

# Use provided branch name or generate one using AI
if ($BranchName) {
    $newBranchName = $BranchName
    Write-Host "Using provided branch name: $newBranchName" -ForegroundColor Green
} else {
    # Use LlmComplete from _Shared.ps1 to generate a nice branch name 
    $branchPrompt = @"
Generate a concise git branch name based on these commit messages:

$commitMessages

Requirements:
- Use lowercase letters, numbers, and hyphens only
- Start with a type prefix (feature/, fix/, chore/, docs/, etc.)
- Keep it under 50 characters
- Make it descriptive but concise
- No spaces or special characters

Return ONLY the branch name, nothing else.
"@

    Write-Host "`nGenerating branch name using AI..." -ForegroundColor Yellow
    $newBranchName = LlmComplete -Prompt $branchPrompt

    if (-not $newBranchName) {
        Write-Error "Failed to generate branch name using AI."
        exit 1
    }

    $newBranchName = $newBranchName.Trim()
    Write-Host "Generated branch name: $newBranchName" -ForegroundColor Green
}

# Check if branch already exists, if so fail
$existingBranch = git branch -a | Where-Object { $_ -match [regex]::Escape($newBranchName) }
if ($existingBranch) {
    Write-Error "Branch '$newBranchName' already exists. Please delete it first or use a different name."
    exit 1
}

# Create a new branch 
Write-Host "`nCreating new branch..." -ForegroundColor Yellow
git checkout -b $newBranchName
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create branch '$newBranchName'"
    exit 1
}

# Push the branch to the remote
Write-Host "`nPushing branch to remote..." -ForegroundColor Yellow
git push -u origin $newBranchName
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to push branch to remote"
    git checkout $currentBranch
    git branch -d $newBranchName
    exit 1
}

# Use gh to create the pull request
Write-Host "`nCreating pull request..." -ForegroundColor Yellow

# Generate PR title using AI
$prTitlePrompt = @"
Based on these commit messages, generate a concise pull request title:

$commitMessages

Requirements:
- Concise and descriptive
- Under 72 characters
- Start with a capital letter
- Focus on the main change/feature
- No quotes or special formatting

Return ONLY the title text, nothing else.
"@

Write-Host "Generating PR title..." -ForegroundColor Yellow
$prTitle = LlmComplete -Prompt $prTitlePrompt
if (-not $prTitle) {
    Write-Error "Failed to generate PR title using AI."
    exit 1
}
$prTitle = $prTitle.Trim()

# Generate PR body using AI
$prBodyPrompt = @"
Based on these commit messages and the full diff, generate a detailed pull request description:

Commit Messages:
$commitMessages

Full Diff:
$fullDiff

Requirements:
- Provide a comprehensive summary of what changes were made and why
- Use proper markdown formatting with headers (##) for different sections
- Include code examples for new methods, classes, or significant changes using \`\`\` code blocks
- Use bullet points for listing multiple changes
- If new functions/methods were added, show their signatures and brief usage examples
- Include any breaking changes or important notes
- Be specific about what was added, changed, fixed, or removed
- Organize the content with sections like: Overview, Changes, Code Examples, Notes

Return ONLY the description text in markdown format, nothing else.
"@

Write-Host "Generating PR body..." -ForegroundColor Yellow
$prBody = LlmComplete -Prompt $prBodyPrompt
if (-not $prBody) {
    Write-Error "Failed to generate PR body using AI."
    exit 1
}
$prBody = $prBody.Trim()

# Fallbacks
if (-not $prTitle) {
    $prTitle = "PR from $newBranchName"
}

if (-not $prBody) {
    $prBody = $commitMessages
}

# Create the pull request
# Write PR body to temporary file to handle special characters and formatting
$tempFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tempFile -Value $prBody -Encoding UTF8

# Use the file for PR body content
$prUrl = gh pr create --title "$prTitle" --body-file "$tempFile" --base $currentBranch 2>&1

# Clean up temporary file
Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nPull request created successfully!" -ForegroundColor Green
    Write-Host "URL: $prUrl" -ForegroundColor Cyan
    
    # Extract PR number from URL
    if ($prUrl -match "/pull/(\d+)") {
        $prNumber = $matches[1]
        
        # Add reviewer if specified
        if ($Reviewer) {
            Write-Host "`nAdding reviewer '$Reviewer'..." -ForegroundColor Yellow
            gh pr edit $prNumber --add-reviewer $Reviewer 2>$null

            if ($LASTEXITCODE -eq 0) {
                Write-Host "Reviewer '$Reviewer' added successfully!" -ForegroundColor Green
            } else {
                Write-Host "Could not add reviewer '$Reviewer' (user may not exist or insufficient permissions)" -ForegroundColor Yellow
            }
        }

        # Approve the pull request if flag is set
        if ($Approve) {
            Write-Host "`nApproving pull request..." -ForegroundColor Yellow

            # Note: gh pr review --approve requires appropriate permissions
            # This might fail if the user doesn't have approval rights
            gh pr review $prNumber --approve 2>$null

            if ($LASTEXITCODE -eq 0) {
                Write-Host "Pull request approved!" -ForegroundColor Green
            } else {
                Write-Host "Could not auto-approve PR (insufficient permissions or org settings)" -ForegroundColor Yellow
            }
        }
        
        # Open PR in browser if flag is set
        if ($Open) {
            Write-Host "`nOpening pull request in browser..." -ForegroundColor Yellow
            Start-Process $prUrl
        }
        
        # Checkout the original branch
        git checkout $currentBranch
        
        Write-Host "`nPull request #$prNumber has been created and is ready for review." -ForegroundColor Green
        Write-Host "Branch '$newBranchName' has been pushed to remote." -ForegroundColor Green
    }
} else {
    Write-Error "Failed to create pull request: $prUrl"
    exit 1
}