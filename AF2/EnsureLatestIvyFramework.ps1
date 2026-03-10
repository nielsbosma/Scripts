$ErrorActionPreference = "Stop"
$repoRoot = "D:\Repos\_Ivy\Ivy-Framework"

# 1) Check and print the current branch
$branch = git -C $repoRoot rev-parse --abbrev-ref HEAD
Write-Host "Current branch: $branch" -ForegroundColor Cyan

# 2) Fail if there are uncommitted or unpushed changes
$status = git -C $repoRoot status --porcelain
if ($status) {
    Write-Error "There are uncommitted changes in the repo:`n$status"
    exit 1
}

$unpushed = git -C $repoRoot log "@{u}..HEAD" --oneline 2>$null
if ($unpushed) {
    Write-Error "There are unpushed commits:`n$unpushed"
    exit 1
}

Write-Host "No uncommitted or unpushed changes." -ForegroundColor Green

# 3) Git pull
Write-Host "`nPulling latest changes..." -ForegroundColor Cyan
git -C $repoRoot pull
if ($LASTEXITCODE -ne 0) { Write-Error "git pull failed"; exit 1 }

# 4) npm install & build in frontend
Write-Host "`nBuilding frontend..." -ForegroundColor Cyan
Push-Location "$repoRoot\src\frontend"
try {
    npm install
    if ($LASTEXITCODE -ne 0) { Write-Error "npm install failed"; exit 1 }
    npm run build
    if ($LASTEXITCODE -ne 0) { Write-Error "npm run build failed"; exit 1 }
} finally {
    Pop-Location
}

# 5) Run Regenerate.ps1 in Ivy.Docs.Shared
Write-Host "`nRunning Regenerate.ps1..." -ForegroundColor Cyan
Push-Location "$repoRoot\src\Ivy.Docs.Shared"
try {
    & .\Regenerate.ps1
    if ($LASTEXITCODE -ne 0) { Write-Error "Regenerate.ps1 failed"; exit 1 }
} finally {
    Pop-Location
}

# 6) dotnet build in src
Write-Host "`nBuilding .NET solution..." -ForegroundColor Cyan
Push-Location "$repoRoot\src"
try {
    dotnet build
    if ($LASTEXITCODE -ne 0) { Write-Error "dotnet build failed"; exit 1 }
} finally {
    Pop-Location
}

Write-Host "`nIvy Framework is up to date and built successfully!" -ForegroundColor Green
