# IvySwitch.ps1
# Simple tool to switch branches across Ivy repositories (git operations only)
# Use IvySwitchBranch.ps1 if you also want dotnet/npm build steps

param(
    [Parameter(Mandatory = $true)]
    [string]$Branch,

    [bool]$Ivy = $true,
    [bool]$IvyFramework = $true,
    [bool]$IvyAgent = $true,
    [bool]$IvyServices = $true
)

$BaseDirectory = "D:\Repos\_Ivy"

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

function Test-BranchExists {
    param([string]$RepoPath, [string]$BranchName)

    Push-Location $RepoPath
    try {
        $localBranch = git branch --list $BranchName 2>$null
        if ($localBranch) { return $true }

        $remoteBranch = git branch -r --list "origin/$BranchName" 2>$null
        if ($remoteBranch) { return $true }

        return $false
    }
    finally {
        Pop-Location
    }
}

function Get-CurrentBranch {
    param([string]$RepoPath)

    Push-Location $RepoPath
    try {
        return (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
    }
    finally {
        Pop-Location
    }
}

function Test-HasUncommittedChanges {
    param([string]$RepoPath)

    Push-Location $RepoPath
    try {
        $status = git status --porcelain 2>$null
        return [bool]$status
    }
    finally {
        Pop-Location
    }
}

function Test-HasUnpushedCommits {
    param([string]$RepoPath)

    Push-Location $RepoPath
    try {
        $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
        $unpushed = git log "origin/$currentBranch..$currentBranch" --oneline 2>$null
        return [bool]$unpushed
    }
    finally {
        Pop-Location
    }
}

# Check if at least one repo is selected
$selectedRepos = $Repos | Where-Object { $_.Enabled }
if ($selectedRepos.Count -eq 0) {
    Write-Host "No repositories selected. Use flags like -Ivy `$true" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "IvySwitch - Target Branch: $Branch" -ForegroundColor Cyan
Write-Host ""

# Pre-flight check
Write-Host "Pre-flight check..." -ForegroundColor Yellow
$hasIssues = $false
$reposToProcess = @()

foreach ($repo in $Repos) {
    if (-not $repo.Enabled) { continue }

    $name = $repo.Name
    $path = $repo.RepoPath

    if (-not (Test-Path $path)) {
        Write-Err "[$name] Repository not found: $path"
        $hasIssues = $true
        continue
    }

    # Fetch latest
    Push-Location $path
    git fetch origin 2>$null
    Pop-Location

    if (-not (Test-BranchExists -RepoPath $path -BranchName $Branch)) {
        Write-Warn "[$name] Branch '$Branch' does not exist - skipping"
        continue
    }

    if (Test-HasUncommittedChanges -RepoPath $path) {
        Write-Err "[$name] Uncommitted changes detected"
        $hasIssues = $true
        continue
    }

    if (Test-HasUnpushedCommits -RepoPath $path) {
        Write-Err "[$name] Unpushed commits detected"
        $hasIssues = $true
        continue
    }

    Write-Success "[$name] Ready"
    $reposToProcess += $repo
}

Write-Host ""

if ($hasIssues) {
    Write-Host "Aborting due to issues above." -ForegroundColor Red
    exit 1
}

if ($reposToProcess.Count -eq 0) {
    Write-Host "No repos to process." -ForegroundColor Yellow
    exit 0
}

# Switch branches
foreach ($repo in $reposToProcess) {
    $name = $repo.Name
    $path = $repo.RepoPath

    Write-Host "[$name]" -ForegroundColor Cyan

    $currentBranch = Get-CurrentBranch -RepoPath $path

    Push-Location $path
    try {
        if ($currentBranch -eq $Branch) {
            Write-Success "Already on '$Branch'"
        }
        else {
            Write-Step "Switching to '$Branch'..."
            git checkout $Branch 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Err "Failed to switch branch"
                continue
            }
            Write-Success "Switched to '$Branch'"
        }

        Write-Step "Pulling latest..."
        git pull 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Pulled latest"
        }
        else {
            Write-Warn "Pull may have had issues"
        }
    }
    finally {
        Pop-Location
    }

    Write-Host ""
}

Write-Host "Done." -ForegroundColor Green
exit 0
