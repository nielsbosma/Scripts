<# 
.SYNOPSIS
  Create a GitHub issue with the current clipboard image embedded, using the current git repo.

.DESCRIPTION
  Detects the nearest .git folder upward from the current location, converts the clipboard image
  to base64 and embeds it directly in a markdown file, then creates a GitHub issue.

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
$fileSize = (Get-Item $pngPath).Length / 1KB
Write-Host "File size: $fileSize KB" -ForegroundColor Gray

# --- Convert to base64 ---
Write-Host "Converting image to base64..." -ForegroundColor Cyan
$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($pngPath))

# GitHub has a limit on issue body size, so we'll use a different approach
# Option 1: Direct base64 embedding (works for smaller images)
if ($fileSize -lt 100) {
    Write-Host "Using direct base64 embedding..." -ForegroundColor Cyan
    $markdownImage = "![Screenshot](data:image/png;base64,$base64)"
    $fullBody = "$Body`n`n$markdownImage"
} else {
    # Option 2: Save to a markdown file and create as attachment
    Write-Host "Image too large for direct embedding. Creating as file attachment..." -ForegroundColor Yellow
    
    # Create a markdown file with the image
    $mdPath = Join-Path $env:TEMP ("issue_$timestamp.md")
    $mdContent = @"
$Body

## Screenshot
Image file: screenshot_$timestamp.png
Size: $fileSize KB

_Note: Copy and paste the image directly into the issue comment to embed it._
"@
    $mdContent | Out-File -FilePath $mdPath -Encoding UTF8
    
    # Create issue with instruction to paste image
    $fullBody = @"
$Body

**📸 Screenshot Instructions:**
1. Open this issue in your browser
2. Drag and drop the image file from: ``$pngPath``
3. Or copy the image to clipboard and paste it directly in a comment

_Image saved at: $pngPath (Size: $fileSize KB)_
"@
}

# --- Create issue ---
Write-Host "Creating issue in $Repo..." -ForegroundColor Cyan
gh issue create --repo $Repo --title $Title --body $fullBody
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Issue created in $Repo" -ForegroundColor Green
    if ($fileSize -ge 100) {
        Write-Host "⚠️  Please manually add the screenshot to the issue:" -ForegroundColor Yellow
        Write-Host "   Image location: $pngPath" -ForegroundColor Yellow
        # Copy path to clipboard for convenience
        Set-Clipboard -Value $pngPath
        Write-Host "   (Path copied to clipboard)" -ForegroundColor Gray
    }
} else {
    Write-Error "Issue creation failed."
}

# Clean up temp files
Remove-Item $pngPath -ErrorAction SilentlyContinue