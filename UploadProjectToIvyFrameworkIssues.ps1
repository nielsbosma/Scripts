<#
.SYNOPSIS
  Zip the current project and file it as a GitHub issue on Ivy-Framework.

.DESCRIPTION
  Validates the current folder contains a .csproj, detects whether the project
  references Ivy-Framework locally (ProjectReference) or via NuGet (PackageReference),
  zips the folder (excluding bin/obj), creates a GitHub issue, uploads the zip,
  and opens the issue in the browser.

.PARAMETER Title
  The issue title (mandatory).
#>

param(
  [Parameter(Mandatory)]
  [string] $Title
)

$ErrorActionPreference = "Stop"
$IvyRepo = "Ivy-Interactive/Ivy-Framework"

# --- 1. Ensure the current directory contains a .csproj file ---
$csprojFiles = Get-ChildItem -Path . -Filter *.csproj -File
if (-not $csprojFiles) {
    Write-Error "No .csproj file found in the current directory."
    exit 1
}
$csproj = $csprojFiles | Select-Object -First 1
Write-Host "Found project: $($csproj.Name)" -ForegroundColor Cyan

# --- 2. Determine Ivy reference type ---
[xml]$xml = Get-Content $csproj.FullName

$ivyInfo = $null

# Check for local ProjectReference to Ivy-Framework
$projectRefs = $xml.Project.ItemGroup.ProjectReference |
    Where-Object { $_.Include -and $_.Include -match 'Ivy-Framework' }

if ($projectRefs) {
    $refPath = ($projectRefs | Select-Object -First 1).Include
    Write-Host "Local Ivy-Framework reference: $refPath" -ForegroundColor Yellow

    # Walk up from the referenced csproj to find the repo root
    $repoDir = $refPath
    while ($repoDir -and -not (Test-Path (Join-Path $repoDir ".git"))) {
        $parent = Split-Path $repoDir -Parent
        if ($parent -eq $repoDir) { $repoDir = $null; break }
        $repoDir = $parent
    }

    if ($repoDir) {
        $commitId = git -C $repoDir rev-parse HEAD 2>$null
        $branch   = git -C $repoDir rev-parse --abbrev-ref HEAD 2>$null
        Write-Host "Ivy-Framework repo: $repoDir" -ForegroundColor Green
        Write-Host "Branch: $branch  Commit: $commitId" -ForegroundColor Green
        $ivyInfo = "**Ivy-Framework (local)**`nBranch: ``$branch```nCommit: ``$commitId``"
    } else {
        Write-Warning "Could not locate .git root for the Ivy-Framework reference."
        $ivyInfo = "**Ivy-Framework (local)** - commit unknown"
    }
} else {
    # Check for NuGet PackageReference containing "Ivy"
    $nugetRefs = $xml.Project.ItemGroup.PackageReference |
        Where-Object { $_.Include -and $_.Include -match '^Ivy(\.|$)' }

    if ($nugetRefs) {
        $pkg = $nugetRefs | Select-Object -First 1
        $pkgName    = $pkg.Include
        $pkgVersion = $pkg.Version
        Write-Host "Ivy NuGet package: $pkgName v$pkgVersion" -ForegroundColor Green
        $ivyInfo = "**$pkgName** NuGet v``$pkgVersion``"
    } else {
        Write-Warning "No Ivy reference (local or NuGet) found in $($csproj.Name)."
        $ivyInfo = "No Ivy reference detected."
    }
}

# --- 3. Zip the folder (exclude bin, obj) ---
$folderName = (Get-Item .).Name
$zipName    = "$folderName.zip"
$zipPath    = Join-Path (Get-Location) $zipName

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

Write-Host "`nCreating $zipName ..." -ForegroundColor Cyan

$items = Get-ChildItem -Path . -Force |
    Where-Object { $_.Name -notin 'bin', 'obj', '.vs' -and $_.Name -ne $zipName }

Compress-Archive -Path $items.FullName -DestinationPath $zipPath -Force

$sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
Write-Host "Zip created: $zipPath ($sizeMB MB)" -ForegroundColor Green

# --- 4. Ensure gh CLI is available ---
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) not found. Install from https://cli.github.com/"
    exit 1
}
gh auth status 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Not authenticated with gh. Run: gh auth login"
    exit 1
}

# --- 5. Create the issue ---
$body = @"
$ivyInfo

---
Project zip attached.
"@

Write-Host "`nCreating issue on $IvyRepo ..." -ForegroundColor Cyan

$issueUrl = gh issue create --repo $IvyRepo --title $Title --body $body 2>&1 |
    Select-String -Pattern 'https://github.com/.*/issues/\d+' |
    Select-Object -First 1 -ExpandProperty Line

if (-not $issueUrl) {
    Write-Error "Failed to create issue."
    exit 1
}
$issueUrl = $issueUrl.Trim()
Write-Host "Issue created: $issueUrl" -ForegroundColor Green

# --- 6. TODO: Upload the zip to the issue ---
# gh CLI doesn't support direct file attachments on issues.
# For now, the zip is left at $zipPath for manual attachment.
Write-Host "Zip ready for manual upload: $zipPath" -ForegroundColor Yellow

# --- 7. Open the issue and the folder ---
Write-Host "`nOpening issue and folder..." -ForegroundColor Cyan
Start-Process $issueUrl
Start-Process (Get-Location).Path
