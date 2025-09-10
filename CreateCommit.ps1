param(
    [switch]$Push
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

# Check that we have any uncommitted changes
$status = git status --porcelain
if (-not $status) {
    Write-Host "No changes to commit." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found uncommitted changes:" -ForegroundColor Green
Write-Host $status

# Stage all changes first to ensure we capture everything in the diff
Write-Host "`nStaging all changes..." -ForegroundColor Yellow
git add -A

# Generate a Diff of all files that have been changed and compile into a single string suitable for an LLM to write a commit message
Write-Host "`nGenerating diff of staged changes..." -ForegroundColor Yellow

# Get the staged changes (which now includes everything)
$fullDiff = git diff --cached

# If no diff content (shouldn't happen after git add -A, but just in case)
if (-not $fullDiff) {
    Write-Error "No changes found after staging"
    exit 1
}

# Prepare prompt for LLM
$prompt = @"
Based on the following git diff, write a concise and descriptive commit message following conventional commit standards.
The message should:
- Start with a type (feat, fix, docs, style, refactor, test, chore, etc.)
- Include a scope in parentheses if applicable
- Have a short description (50 chars or less for the first line)
- Optionally include a longer description after a blank line if needed

Git Diff:
$fullDiff

Write only the commit message, nothing else:
"@

Write-Host "`nGenerating commit message..." -ForegroundColor Yellow

# Use LlmComplete from _Shared.ps1 to generate a commit message
$commitMessage = LlmComplete -Prompt $prompt

if (-not $commitMessage) {
    Write-Error "Failed to generate commit message"
    exit 1
}

# Display the generated message
Write-Host "`nGenerated commit message:" -ForegroundColor Green
Write-Host $commitMessage -ForegroundColor Cyan

# Create a commit with the generated message
Write-Host "`nCreating commit..." -ForegroundColor Yellow
git commit -m $commitMessage

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nCommit created successfully!" -ForegroundColor Green
    
    # Show the commit
    Write-Host "`nCommit details:" -ForegroundColor Yellow
    git log -1 --oneline
    
    # Push if -Push flag is set
    if ($Push) {
        Write-Host "`nPushing to remote..." -ForegroundColor Yellow
        git push
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Push successful!" -ForegroundColor Green
        } else {
            Write-Error "Failed to push to remote"
            exit 1
        }
    }
} else {
    Write-Error "Failed to create commit"
    exit 1
}



