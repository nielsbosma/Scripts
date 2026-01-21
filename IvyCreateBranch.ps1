# IvyCreateBranch.ps1
# Creates a new branch across selected Ivy repositories
# 1. Checks branch doesn't exist in origin
# 2. Switches to main branch
# 3. Creates and pushes the new branch

param(
    [Parameter(Mandatory = $true)]
    [string]$Branch,

    [switch]$Ivy,
    [switch]$IvyFramework,
    [switch]$IvyAgent,
    [switch]$IvyServices,
    [switch]$SkipSwitch
)

$BaseDirectory = "D:\Repos\_Ivy"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Repository configuration
$Repos = @(
    @{
        Name = "Ivy"
        Enabled = $Ivy
        RepoPath = "D:\Repos\_Ivy\Ivy"
    },
    @{
        Name = "Ivy-Framework"
        Enabled = $IvyFramework
        RepoPath = "D:\Repos\_Ivy\Ivy-Framework"
    },
    @{
        Name = "Ivy-Agent"
        Enabled = $IvyAgent
        RepoPath = "D:\Repos\_Ivy\Ivy-Agent"
    },
    @{
        Name = "Ivy-Services"
        Enabled = $IvyServices
        RepoPath = "D:\Repos\_Ivy\Ivy-Services"
    }
)

function Write-Step {
    param([string]$Message)
    Write-Host "  -> $Message" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [!] $Message" -ForegroundColor DarkYellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "  [X] $Message" -ForegroundColor Red
}

function Test-BranchExistsInOrigin {
    param([string]$RepoPath, [string]$BranchName)

    Push-Location $RepoPath
    try {
        git fetch origin 2>$null
        $remoteBranch = git branch -r --list "origin/$BranchName" 2>$null
        return [bool]$remoteBranch
    }
    finally {
        Pop-Location
    }
}

# Check if at least one repo is selected
$selectedRepos = $Repos | Where-Object { $_.Enabled }
if ($selectedRepos.Count -eq 0) {
    Write-Host "No repositories selected. Use flags like -Ivy -IvyFramework" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "IvyCreateBranch - New Branch: $Branch" -ForegroundColor Cyan
Write-Host ""

# ============================================
# STEP 1: Check branch doesn't exist in origin
# ============================================
Write-Host "Step 1: Checking branch doesn't exist in origin..." -ForegroundColor Yellow
Write-Host ""

$branchExists = $false

foreach ($repo in $Repos) {
    if (-not $repo.Enabled) { continue }

    $name = $repo.Name
    $path = $repo.RepoPath

    if (-not (Test-Path $path)) {
        Write-Err "[$name] Repository not found: $path"
        exit 1
    }

    if (Test-BranchExistsInOrigin -RepoPath $path -BranchName $Branch) {
        Write-Err "[$name] Branch '$Branch' already exists in origin!"
        $branchExists = $true
    }
    else {
        Write-Success "[$name] Branch '$Branch' does not exist in origin"
    }
}

Write-Host ""

if ($branchExists) {
    Write-Host "Aborting: Branch already exists in one or more repositories." -ForegroundColor Red
    exit 1
}

# ============================================
# STEP 2: Switch to main branch (unless skipped)
# ============================================
if (-not $SkipSwitch) {
    Write-Host "Step 2: Switching to 'main' branch..." -ForegroundColor Yellow
    Write-Host ""

    $switchScript = Join-Path $ScriptDir "IvySwitch.ps1"

    if (-not (Test-Path $switchScript)) {
        Write-Host "IvySwitch.ps1 not found at: $switchScript" -ForegroundColor Red
        exit 1
    }

    & $switchScript -Branch "main" -Ivy:$Ivy -IvyFramework:$IvyFramework -IvyAgent:$IvyAgent -IvyServices:$IvyServices

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to switch to main branch. Aborting." -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "Step 2: Skipping switch to main (creating branch from current HEAD)" -ForegroundColor Yellow
    Write-Host ""
}

# ============================================
# STEP 3: Create branch and push to origin
# ============================================
Write-Host "Step 3: Creating branch '$Branch' and pushing to origin..." -ForegroundColor Yellow
Write-Host ""

$hasErrors = $false

foreach ($repo in $Repos) {
    if (-not $repo.Enabled) { continue }

    $name = $repo.Name
    $path = $repo.RepoPath

    Write-Host "[$name]" -ForegroundColor Cyan

    Push-Location $path
    try {
        # Create local branch
        Write-Step "Creating local branch '$Branch'..."
        git checkout -b $Branch 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            Write-Err "Failed to create local branch"
            $hasErrors = $true
            continue
        }

        # Push to origin with upstream tracking
        Write-Step "Pushing to origin..."
        git push -u origin $Branch 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Success "Branch '$Branch' created and pushed"
        }
        else {
            Write-Err "Failed to push to origin"
            $hasErrors = $true
        }
    }
    finally {
        Pop-Location
    }

    Write-Host ""
}

if ($hasErrors) {
    Write-Host "Completed with errors." -ForegroundColor Red
    exit 1
}
else {
    Write-Host "Branch '$Branch' created successfully in all selected repositories!" -ForegroundColor Green
    exit 0
}
