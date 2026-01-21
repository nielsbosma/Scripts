# Tool to switch branches across Ivy repositories
# Performs git operations, dotnet builds, and npm builds as configured

param(
    [Parameter(Mandatory = $true)]
    [string]$Branch,

    [bool]$DotnetClean = $true,
    [bool]$DotnetRestore = $true,
    [bool]$DotnetBuild = $true,
    [bool]$NpmInstall = $true,
    [bool]$NpmBuild = $true,
    [bool]$Ivy = $true,
    [bool]$IvyFramework = $true,
    [bool]$IvyAgent = $true,
    [bool]$IvyServices = $true
)

$BaseDirectory = "D:\Repos\_Ivy"

# Repository configuration: Name, Enabled flag, Solution path
$Repos = @(
    @{
        Name = "Ivy"
        Enabled = $Ivy
        SolutionPath = "D:\Repos\_Ivy\Ivy\Ivy.sln"
        RepoPath = "D:\Repos\_Ivy\Ivy"
    },
    @{
        Name = "Ivy-Framework"
        Enabled = $IvyFramework
        SolutionPath = "D:\Repos\_Ivy\Ivy-Framework\src\Ivy-Framework.sln"
        RepoPath = "D:\Repos\_Ivy\Ivy-Framework"
    },
    @{
        Name = "Ivy-Agent"
        Enabled = $IvyAgent
        SolutionPath = "D:\Repos\_Ivy\Ivy-Agent\Ivy-Agent.sln"
        RepoPath = "D:\Repos\_Ivy\Ivy-Agent"
    },
    @{
        Name = "Ivy-Services"
        Enabled = $IvyServices
        SolutionPath = "D:\Repos\_Ivy\Ivy-Services\Ivy-Services.sln"
        RepoPath = "D:\Repos\_Ivy\Ivy-Services"
    }
)

function Write-RepoHeader {
    param([string]$RepoName)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " Processing: $RepoName" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Message)
    Write-Host "  -> $Message" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "  ⚠ $Message" -ForegroundColor DarkYellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "  ✗ $Message" -ForegroundColor Red
}

function Test-BranchExists {
    param([string]$RepoPath, [string]$BranchName)

    Push-Location $RepoPath
    try {
        # Check local branches
        $localBranch = git branch --list $BranchName 2>$null
        if ($localBranch) {
            return $true
        }

        # Check remote branches
        $remoteBranch = git branch -r --list "origin/$BranchName" 2>$null
        if ($remoteBranch) {
            return $true
        }

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

function Switch-ToBranch {
    param([string]$RepoPath, [string]$BranchName)

    Push-Location $RepoPath
    try {
        git checkout $BranchName 2>&1 | Out-Null
        return $LASTEXITCODE -eq 0
    }
    finally {
        Pop-Location
    }
}

function Update-FromOrigin {
    param([string]$RepoPath)

    Push-Location $RepoPath
    try {
        git pull 2>&1
        return $LASTEXITCODE -eq 0
    }
    finally {
        Pop-Location
    }
}

function Invoke-DotnetClean {
    param([string]$SolutionPath)

    Write-Step "Running dotnet clean..."
    dotnet clean $SolutionPath
    return $LASTEXITCODE -eq 0
}

function Invoke-DotnetRestore {
    param([string]$SolutionPath)

    Write-Step "Running dotnet restore..."
    dotnet restore $SolutionPath
    return $LASTEXITCODE -eq 0
}

function Invoke-DotnetBuild {
    param([string]$SolutionPath)

    Write-Step "Running dotnet build..."
    dotnet build $SolutionPath
    return $LASTEXITCODE -eq 0
}

# Main execution
Write-Host ""
Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║       Ivy Branch Switcher Tool         ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""
Write-Host "Target Branch: $Branch" -ForegroundColor White
Write-Host "DotnetClean: $DotnetClean | DotnetRestore: $DotnetRestore | DotnetBuild: $DotnetBuild" -ForegroundColor Gray
Write-Host "NpmInstall: $NpmInstall | NpmBuild: $NpmBuild" -ForegroundColor Gray
Write-Host ""

# ============================================
# PRE-FLIGHT CHECK: Verify all repos are clean
# ============================================
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host " Pre-flight Check: Verifying all repos" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host ""

$hasIssues = $false
$reposToProcess = @()

foreach ($repo in $Repos) {
    # Skip disabled repos
    if (-not $repo.Enabled) {
        continue
    }

    # Verify repo exists
    if (-not (Test-Path $repo.RepoPath)) {
        Write-Error "[$($repo.Name)] Repository path does not exist: $($repo.RepoPath)"
        $hasIssues = $true
        continue
    }

    # Check if branch exists
    if (-not (Test-BranchExists -RepoPath $repo.RepoPath -BranchName $Branch)) {
        Write-Warning "[$($repo.Name)] Branch '$Branch' does not exist - will be skipped"
        continue
    }

    # Check current branch
    $currentBranch = Get-CurrentBranch -RepoPath $repo.RepoPath
    $alreadyOnBranch = $currentBranch -eq $Branch

    # Check for uncommitted changes
    if (Test-HasUncommittedChanges -RepoPath $repo.RepoPath) {
        Write-Error "[$($repo.Name)] UNCOMMITTED CHANGES DETECTED"
        $hasIssues = $true
        continue
    }

    # Check for unpushed commits
    if (Test-HasUnpushedCommits -RepoPath $repo.RepoPath) {
        Write-Error "[$($repo.Name)] UNPUSHED COMMITS DETECTED"
        $hasIssues = $true
        continue
    }

    if ($alreadyOnBranch) {
        Write-Success "[$($repo.Name)] Already on branch '$Branch' - clean"
    }
    else {
        Write-Success "[$($repo.Name)] Clean and ready"
    }
    $reposToProcess += $repo
}

Write-Host ""

if ($hasIssues) {
    Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║   ABORTING: Issues detected above      ║" -ForegroundColor Red
    Write-Host "║   Please resolve before continuing     ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    exit 1
}

if ($reposToProcess.Count -eq 0) {
    Write-Host "No repos to process. Exiting." -ForegroundColor Yellow
    exit 0
}

Write-Host "Pre-flight check passed. Processing $($reposToProcess.Count) repo(s)..." -ForegroundColor Green
Write-Host ""

# ============================================
# MAIN PROCESSING: Switch branches and build
# ============================================
foreach ($repo in $reposToProcess) {
    Write-RepoHeader $repo.Name

    # Check current branch
    $currentBranch = Get-CurrentBranch -RepoPath $repo.RepoPath
    $alreadyOnBranch = $currentBranch -eq $Branch

    if ($alreadyOnBranch) {
        Write-Success "Already on branch '$Branch'"
    }
    else {
        # Switch to branch
        Write-Step "Switching to branch '$Branch'..."
        if (-not (Switch-ToBranch -RepoPath $repo.RepoPath -BranchName $Branch)) {
            Write-Error "Failed to switch to branch '$Branch'"
            continue
        }
        Write-Success "Switched to branch '$Branch'"
    }

    # Pull latest
    Write-Step "Pulling latest changes from origin..."
    if (-not (Update-FromOrigin -RepoPath $repo.RepoPath)) {
        Write-Warning "Pull may have had issues - check output above"
    }
    else {
        Write-Success "Pulled latest changes"
    }

    # Step 5-7: Dotnet operations
    if ($DotnetClean) {
        if (-not (Invoke-DotnetClean -SolutionPath $repo.SolutionPath)) {
            Write-Warning "dotnet clean had issues"
        }
        else {
            Write-Success "dotnet clean completed"
        }
    }

    if ($DotnetRestore) {
        if (-not (Invoke-DotnetRestore -SolutionPath $repo.SolutionPath)) {
            Write-Warning "dotnet restore had issues"
        }
        else {
            Write-Success "dotnet restore completed"
        }
    }

    if ($DotnetBuild) {
        if (-not (Invoke-DotnetBuild -SolutionPath $repo.SolutionPath)) {
            Write-Warning "dotnet build had issues"
        }
        else {
            Write-Success "dotnet build completed"
        }
    }

    # Step 8: Special handling for Ivy-Framework
    if ($repo.Name -eq "Ivy-Framework" -and $repo.Enabled) {
        Write-Host ""
        Write-Host "  --- Ivy-Framework Additional Steps ---" -ForegroundColor Cyan

        # Run Regenerate.ps1
        $regeneratePath = "D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared\Regenerate.ps1"
        $regenerateDir = "D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared"
        if (Test-Path $regeneratePath) {
            Write-Step "Running Regenerate.ps1..."
            Push-Location $regenerateDir
            & $regeneratePath
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Regenerate.ps1 completed"
            }
            else {
                Write-Warning "Regenerate.ps1 had issues"
            }
            Pop-Location
        }
        else {
            Write-Warning "Regenerate.ps1 not found at: $regeneratePath"
        }

        # Build again after regeneration
        if ($DotnetBuild) {
            Write-Step "Running dotnet build again (post-regeneration)..."
            if (-not (Invoke-DotnetBuild -SolutionPath $repo.SolutionPath)) {
                Write-Warning "Post-regeneration dotnet build had issues"
            }
            else {
                Write-Success "Post-regeneration dotnet build completed"
            }
        }

        # NPM operations
        $frontendPath = "D:\Repos\_Ivy\Ivy-Framework\src\frontend"
        if (Test-Path $frontendPath) {
            if ($NpmInstall) {
                Write-Step "Running npm install in frontend..."
                Push-Location $frontendPath
                npm install
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "npm install completed"
                }
                else {
                    Write-Warning "npm install had issues"
                }
                Pop-Location
            }

            if ($NpmBuild) {
                Write-Step "Running npm run build in frontend..."
                Push-Location $frontendPath
                npm run build
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "npm run build completed"
                }
                else {
                    Write-Warning "npm run build had issues"
                }
                Pop-Location
            }
        }
        else {
            Write-Warning "Frontend path not found: $frontendPath"
        }
    }
}

Write-Host ""
Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║            Process Complete            ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""
