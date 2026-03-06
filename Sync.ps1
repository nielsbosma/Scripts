$repos = @(
    "D:\Repos\_Ivy\Ivy-Agent",
    "D:\Repos\_Ivy\Ivy",
    "D:\Repos\_Ivy\Ivy-Framework",
    "D:\Repos\_Ivy\Ivy-Mcp",
    "D:\Repos\_Personal\Scripts"
)

$prompt = @"
Look at all uncommitted changes (staged and unstaged, including untracked files) in this repo.
Group them into logical commits that belong together — files that are part of the same feature, fix, or change should be in the same commit.
For each logical group:
1. Stage only the relevant files (use git add with specific file paths, not -A)
2. Commit with a conventional commit message (feat/fix/refactor/chore etc.)
If there are no changes, do nothing.
Do NOT push or pull.
"@

foreach ($repo in $repos) {
    $name = Split-Path $repo -Leaf
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $name" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    if (-not (Test-Path $repo)) {
        Write-Host "Repository not found: $repo" -ForegroundColor Red
        continue
    }

    # Check for changes
    $status = git -C $repo status --porcelain
    if ($status) {
        Write-Host "Changes found, creating logical commits..." -ForegroundColor Yellow
        Push-Location $repo
        claude --dangerously-skip-permissions -p $prompt
        $exitCode = $LASTEXITCODE
        Pop-Location
        if ($exitCode -ne 0) {
            Write-Host "Claude commit failed for $name" -ForegroundColor Red
            continue
        }
    } else {
        Write-Host "No changes to commit." -ForegroundColor DarkGray
    }

    # Pull with rebase
    Write-Host "Pulling..." -ForegroundColor Yellow
    git -C $repo pull --rebase
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Pull failed for $name" -ForegroundColor Red
        continue
    }

    # Push
    Write-Host "Pushing..." -ForegroundColor Yellow
    git -C $repo push
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Push failed for $name" -ForegroundColor Red
        continue
    }

    Write-Host "$name synced." -ForegroundColor Green
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Done" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
