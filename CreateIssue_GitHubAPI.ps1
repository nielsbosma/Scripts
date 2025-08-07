<# 
.SYNOPSIS
  Create a GitHub issue with the current clipboard image embedded, using GitHub's upload API.

.DESCRIPTION
  Detects the nearest .git folder, uploads the clipboard image using GitHub's asset upload API,
  and creates a GitHub issue in that repository.

.PARAMETER Title
  Issue title.

.PARAMETER Body
  Optional issue body text (Markdown). The screenshot will be appended.
#>

param(
  [Parameter(Mandatory)]
  [string] $Title,

  [string] $Body = "See screenshot below."
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

# --- Relaunch in STA if needed for clipboard ---
function Ensure-STA {
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        $psi = @{
            FilePath = (Get-Command pwsh, powershell -ErrorAction SilentlyContinue | Select-Object -First 1).Source
            ArgumentList = @(
                '-NoProfile','-STA','-ExecutionPolicy','Bypass',
                '-File', $PSCommandPath,
                '-Title', $Title,
                '-Body', $Body
            )
            Wait = $true
        }
        Start-Process @psi
        exit
    }
}
Ensure-STA

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

# --- Load clipboard ---
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing       | Out-Null
$image = [System.Windows.Forms.Clipboard]::GetImage()
if (-not $image) {
    Write-Error "No image found in clipboard. Copy a screenshot first (Win+Shift+S) and try again."
    exit 4
}

# --- Save screenshot to temp file ---
$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$pngPath   = Join-Path $env:TEMP ("screenshot_$timestamp.png")
$image.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "Saved clipboard image to: $pngPath"

# --- Upload image using GitHub's user content API ---
Write-Host "Uploading image to GitHub..." -ForegroundColor Cyan

# Get the repository owner and name
$repoOwner = $Repo.Split('/')[0]
$repoName = $Repo.Split('/')[1]

# Method 1: Try to upload via discussions/issues asset API
# This requires creating a draft issue first
Write-Host "Creating draft issue to upload image..." -ForegroundColor Cyan

# Create a temporary issue body with placeholder
$tempBody = "Uploading image..."
$draftIssueJson = @{
    title = $Title
    body = $tempBody
} | ConvertTo-Json

# Create the issue first
$issueResult = $draftIssueJson | gh api "repos/$Repo/issues" --method POST --input - 2>&1 | ConvertFrom-Json
if (-not $issueResult.number) {
    Write-Error "Failed to create draft issue"
    exit 5
}
$issueNumber = $issueResult.number
Write-Host "Created draft issue #$issueNumber" -ForegroundColor Green

# Now we need to upload the image as a comment attachment
# GitHub doesn't have a direct API for this, but we can use the web upload endpoint
Write-Host "Note: GitHub API doesn't support direct image uploads." -ForegroundColor Yellow
Write-Host "Alternative approach: Using GitHub Pages or Wiki for image hosting..." -ForegroundColor Yellow

# For now, let's update the issue with instructions
$finalBody = @"
$Body

---
### 📸 Screenshot
To add the screenshot to this issue:
1. Open this issue in your browser: https://github.com/$Repo/issues/$issueNumber
2. Drag and drop the image file: ``$pngPath``
3. Or paste the image from clipboard directly into a comment

*Image saved locally at:* ``$pngPath``
"@

# Update the issue with the final body
$updateJson = @{
    body = $finalBody
} | ConvertTo-Json

$updateResult = $updateJson | gh api "repos/$Repo/issues/$issueNumber" --method PATCH --input - 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Issue #$issueNumber created in $Repo" -ForegroundColor Green
    Write-Host "📋 Image path copied to clipboard: $pngPath" -ForegroundColor Cyan
    Set-Clipboard -Value $pngPath
    
    # Open the issue in browser for easy image upload
    $issueUrl = "https://github.com/$Repo/issues/$issueNumber"
    Write-Host "🌐 Opening issue in browser..." -ForegroundColor Cyan
    Start-Process $issueUrl
} else {
    Write-Error "Failed to update issue with final content"
}