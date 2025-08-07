<# 
.SYNOPSIS
  DEBUG VERSION: Create a GitHub issue with the current clipboard image embedded, using the current git repo.

.DESCRIPTION
  Detects the nearest .git folder upward from the current location, uploads the clipboard image
  to a secret Gist, and creates a GitHub issue in that repository.

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

$ErrorActionPreference = "Stop"

Write-Host "🔍 DEBUG: Script started" -ForegroundColor Cyan
Write-Host "   Title: $Title" -ForegroundColor Cyan
Write-Host "   Body: $Body" -ForegroundColor Cyan

# --- Function: Find the root of the current git repository ---
function Find-GitRepository {
    Write-Host "🔍 DEBUG: Looking for git repository..." -ForegroundColor Cyan
    $currentPath = Get-Location
    Write-Host "   Starting from: $currentPath" -ForegroundColor Cyan
    
    while ($currentPath) {
        $gitPath = Join-Path $currentPath ".git"
        Write-Host "   Checking: $gitPath" -ForegroundColor Gray
        if (Test-Path $gitPath) {
            Write-Host "   ✓ Found git repo at: $currentPath" -ForegroundColor Green
            return $currentPath
        }
        $parent = Split-Path $currentPath -Parent
        if ($parent -eq $currentPath) { 
            Write-Host "   Reached filesystem root" -ForegroundColor Yellow
            break 
        }
        $currentPath = $parent
    }
    Write-Host "   ✗ No git repository found" -ForegroundColor Red
    return $null
}

# --- Relaunch in STA if needed for clipboard ---
function Ensure-STA {
    $apartmentState = [Threading.Thread]::CurrentThread.ApartmentState
    Write-Host "🔍 DEBUG: Current thread apartment state: $apartmentState" -ForegroundColor Cyan
    
    if ($apartmentState -ne 'STA') {
        Write-Host "   Relaunching in STA mode..." -ForegroundColor Yellow
        $pwshExe = (Get-Command pwsh, powershell -ErrorAction SilentlyContinue | Select-Object -First 1).Source
        Write-Host "   Using: $pwshExe" -ForegroundColor Gray
        
        $psi = @{
            FilePath = $pwshExe
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
    Write-Host "   ✓ Already in STA mode" -ForegroundColor Green
}
Ensure-STA

# --- Ensure GitHub CLI is available and authenticated ---
Write-Host "🔍 DEBUG: Checking GitHub CLI..." -ForegroundColor Cyan
$ghCmd = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghCmd) {
    Write-Error "GitHub CLI (gh) not found. Install from https://cli.github.com/ and run 'gh auth login'."
    exit 1
}
Write-Host "   ✓ Found gh at: $($ghCmd.Source)" -ForegroundColor Green

Write-Host "🔍 DEBUG: Checking gh authentication..." -ForegroundColor Cyan
$authOutput = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "   Auth output: $authOutput" -ForegroundColor Red
    Write-Error "You're not authenticated with gh. Run: gh auth login"
    exit 1
}
Write-Host "   ✓ Authenticated" -ForegroundColor Green

# --- Find the repo ---
Write-Host "🔍 DEBUG: Finding repository..." -ForegroundColor Cyan
$repoPath = Find-GitRepository
if (-not $repoPath) {
    Write-Error "No .git folder found in current or parent directories."
    exit 2
}

Push-Location $repoPath
try {
    Write-Host "🔍 DEBUG: Getting repo info from gh..." -ForegroundColor Cyan
    $Repo = gh repo view --json nameWithOwner --jq ".nameWithOwner" 2>&1
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -ne 0) {
        Write-Host "   Exit code: $exitCode" -ForegroundColor Red
        Write-Host "   Output: $Repo" -ForegroundColor Red
        Write-Error "gh repo view failed"
        exit 3
    }
    
    if (-not $Repo) {
        Write-Error "Could not determine GitHub repository from current folder."
        exit 3
    }
    Write-Host "   ✓ Repository: $Repo" -ForegroundColor Green
} finally {
    Pop-Location
}

# --- Load clipboard ---
Write-Host "🔍 DEBUG: Loading Windows Forms assemblies..." -ForegroundColor Cyan
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop | Out-Null
    Write-Host "   ✓ Assemblies loaded" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Failed to load assemblies: $_" -ForegroundColor Red
    throw
}

Write-Host "🔍 DEBUG: Getting clipboard image..." -ForegroundColor Cyan
try {
    $image = [System.Windows.Forms.Clipboard]::GetImage()
    if (-not $image) {
        Write-Host "   ✗ No image in clipboard" -ForegroundColor Red
        Write-Error "No image found in clipboard. Copy a screenshot first (Win+Shift+S) and try again."
        exit 4
    }
    Write-Host "   ✓ Image found: $($image.Width)x$($image.Height) pixels" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Error accessing clipboard: $_" -ForegroundColor Red
    throw
}

# --- Save screenshot to temp file ---
Write-Host "🔍 DEBUG: Saving image to temp file..." -ForegroundColor Cyan
$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$pngPath   = Join-Path $env:TEMP ("screenshot_$timestamp.png")
try {
    $image.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "   ✓ Saved to: $pngPath" -ForegroundColor Green
    Write-Host "   File size: $((Get-Item $pngPath).Length / 1KB) KB" -ForegroundColor Gray
} catch {
    Write-Host "   ✗ Failed to save image: $_" -ForegroundColor Red
    throw
}

# --- Upload to Gist ---
Write-Host "🔍 DEBUG: Creating Gist..." -ForegroundColor Cyan
$desc = "Issue image for $Repo ($([DateTime]::UtcNow.ToString('u')))"
Write-Host "   Description: $desc" -ForegroundColor Gray

$gistOutput = gh gist create -p -d $desc $pngPath 2>&1
$exitCode = $LASTEXITCODE

Write-Host "   Exit code: $exitCode" -ForegroundColor Gray
Write-Host "   Output: $gistOutput" -ForegroundColor Gray

if ($exitCode -ne 0) {
    Write-Host "   ✗ Failed to create Gist" -ForegroundColor Red
    Write-Error "Failed to create Gist. Your org may block Gists."
    exit 5
}

$gistUrl = $gistOutput | Where-Object { $_ -match '^https://gist\.github\.com/' } | Select-Object -First 1
if (-not $gistUrl) {
    Write-Host "   ✗ Could not parse Gist URL from output" -ForegroundColor Red
    Write-Error "Could not parse Gist URL"
    exit 5
}
Write-Host "   ✓ Gist created: $gistUrl" -ForegroundColor Green

$gistId = ($gistUrl -split '/')[-1]
Write-Host "   Gist ID: $gistId" -ForegroundColor Gray

# --- Get raw URL ---
Write-Host "🔍 DEBUG: Getting raw URL..." -ForegroundColor Cyan
$fileName = [IO.Path]::GetFileName($pngPath)
Write-Host "   File name: $fileName" -ForegroundColor Gray

$rawUrl = gh api "gists/$gistId" --jq ".files[\`"$fileName\`"].raw_url" 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host "   Exit code: $exitCode" -ForegroundColor Red
    Write-Host "   Output: $rawUrl" -ForegroundColor Red
    Write-Error "Failed to get raw URL"
    exit 5
}
Write-Host "   ✓ Raw URL: $rawUrl" -ForegroundColor Green

# --- Create issue ---
Write-Host "🔍 DEBUG: Creating issue..." -ForegroundColor Cyan
$fullBody = @"
$Body

![$fileName]($rawUrl)
"@

Write-Host "   Full body:" -ForegroundColor Gray
Write-Host $fullBody -ForegroundColor DarkGray

$issueOutput = gh issue create --repo $Repo --title $Title --body $fullBody 2>&1
$exitCode = $LASTEXITCODE

Write-Host "   Exit code: $exitCode" -ForegroundColor Gray
Write-Host "   Output: $issueOutput" -ForegroundColor Gray

if ($exitCode -eq 0) {
    Write-Host "✅ Issue created in $Repo with embedded screenshot." -ForegroundColor Green
} else {
    Write-Host "   ✗ Issue creation failed" -ForegroundColor Red
    Write-Error "Issue creation failed."
}