<# 
.SYNOPSIS
  Create a GitHub issue in the current git repository.

.DESCRIPTION
  Detects the nearest .git folder upward from the current location and creates a GitHub issue.
  Automatically opens the issue in your default browser.

.PARAMETER Title
  Issue title.

.PARAMETER Body
  Optional issue body text (Markdown).
#>

param(
  [Parameter(Mandatory)]
  [string] $Title,

  [string] $Body = ""
)

# --- Function: Find the root of the current git repository ---
function Find-GitRepository {
    $currentPath = Get-Location
    while ($currentPath) {
        if (Test-Path (Join-Path $currentPath ".git")) {
            return $currentPath
        }
        $parent = Split-Path $currentPath -Parent
        if ($parent -eq $currentPath) { break } # reached root
        $currentPath = $parent
    }
    return $null
}

# --- Ensure GitHub CLI is available and authenticated ---
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) not found. Install from https://cli.github.com/ and run 'gh auth login'."
    exit 1
}
gh auth status 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "You're not authenticated with gh. Run: gh auth login"
    exit 1
}

# --- Find the repo ---
$repoPath = Find-GitRepository
if (-not $repoPath) {
    Write-Error "No .git folder found in current or parent directories."
    exit 2
}
Push-Location $repoPath
try {
    $Repo = gh repo view --json nameWithOwner --jq ".nameWithOwner" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $Repo) {
        Write-Error "Could not determine GitHub repository from current folder."
        exit 3
    }
} finally {
    Pop-Location
}

Write-Host "Repository: $Repo" -ForegroundColor Green

# --- Create the issue ---
Write-Host "Creating issue..." -ForegroundColor Cyan
if ($Body) {
    $issueOutput = gh issue create --repo $Repo --title $Title --body $Body 2>&1
} else {
    # If no body provided, use a space to avoid the prompt
    $issueOutput = gh issue create --repo $Repo --title $Title --body " " 2>&1
}
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create issue: $issueOutput"
    exit 5
}

# Parse issue URL from output
$issueUrl = $issueOutput | Where-Object { $_ -match 'https://github.com/.*/issues/\d+' } | Select-Object -First 1
if ($issueUrl) {
    Write-Host "Issue created: $issueUrl" -ForegroundColor Green
    
    # Open in browser
    Write-Host "Opening issue in browser..." -ForegroundColor Cyan
    Start-Process $issueUrl
} else {
    Write-Host "Issue created successfully!" -ForegroundColor Green
}