$repos = @(
    "D:\Repos\_Ivy\Ivy-Agent",
    "D:\Repos\_Ivy\Ivy",
    "D:\Repos\_Ivy\Ivy-Framework",
    "D:\Repos\_Ivy\Ivy-Mcp",
    "D:\Repos\_Ivy\Ivy-Agent-Test-Data"
)

$hours = 24
$since = (Get-Date).AddHours(-$hours).ToString("yyyy-MM-ddTHH:mm:ss")

# Ensure VS Code is configured as git difftool
git config --global diff.tool vscode
git config --global difftool.vscode.cmd 'code --wait --diff $LOCAL $REMOTE'
git config --global difftool.prompt false

$commits = @()

foreach ($repo in $repos) {
    $name = Split-Path $repo -Leaf

    if (-not (Test-Path $repo)) {
        continue
    }

    $branch = git -C $repo rev-parse --abbrev-ref HEAD 2>$null
    if (-not $branch) { continue }

    $remote = git -C $repo rev-parse --verify "origin/$branch" 2>$null
    if ($remote) {
        $logArgs = @("-C", $repo, "log", "origin/$branch..HEAD", "--since=$since", "--format=%H|%s|%ci")
    } else {
        $logArgs = @("-C", $repo, "log", "--since=$since", "--format=%H|%s|%ci")
    }

    $lines = git @logArgs 2>$null
    if (-not $lines) { continue }

    foreach ($line in $lines) {
        $parts = $line -split '\|', 3
        if ($parts.Count -ge 3) {
            $commits += [PSCustomObject]@{
                Repo   = $name
                Hash   = $parts[0]
                Commit = $parts[1]
                Date   = [DateTime]::Parse($parts[2])
                Path   = $repo
            }
        }
    }
}

if ($commits.Count -eq 0) {
    Write-Host "No unpushed commits found in the last $hours hours." -ForegroundColor Yellow
    exit
}

$commits = $commits | Sort-Object Date -Descending

function Show-CommitList {
    Write-Host ""
    Write-Host "Unpushed commits (last $hours hours):" -ForegroundColor Cyan
    Write-Host ""

    $maxIdx = "$($commits.Count)".Length
    $maxRepo = ($commits | ForEach-Object { $_.Repo.Length } | Measure-Object -Maximum).Maximum

    $header = " " * ($maxIdx + 2) + "Repo".PadRight($maxRepo) + "  Commit"
    $separator = " " * ($maxIdx + 2) + ("-" * $maxRepo) + "  " + ("-" * 50)
    Write-Host $header -ForegroundColor DarkGray
    Write-Host $separator -ForegroundColor DarkGray

    $i = 1
    foreach ($c in $commits) {
        $idx = "$i".PadLeft($maxIdx)
        Write-Host "$idx) " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($c.Repo.PadRight($maxRepo))" -NoNewline -ForegroundColor Yellow
        Write-Host "  $($c.Commit)" -ForegroundColor White
        $i++
    }
    Write-Host ""
}

function Show-FileList($selected) {
    $files = git -C $selected.Path diff-tree --no-commit-id --name-status -r $selected.Hash
    $fileList = @()
    foreach ($f in $files) {
        if ($f -match '^(\w)\t(.+)$') {
            $status = switch ($Matches[1]) {
                'A' { '+' }
                'D' { '-' }
                'M' { '~' }
                default { $Matches[1] }
            }
            $fileList += [PSCustomObject]@{
                Status = $status
                RawStatus = $Matches[1]
                File   = $Matches[2]
            }
        }
    }
    return $fileList
}

function Review-Commit($selected) {
    $fileList = Show-FileList $selected

    while ($true) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host " [$($selected.Repo)] $($selected.Commit)" -ForegroundColor Cyan
        Write-Host " $($selected.Hash.Substring(0,8))" -ForegroundColor DarkGray
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        $i = 1
        foreach ($f in $fileList) {
            $idx = "$i".PadLeft(3)
            $color = switch ($f.Status) {
                '+' { 'Green' }
                '-' { 'Red' }
                '~' { 'Yellow' }
                default { 'White' }
            }
            Write-Host "$idx) " -NoNewline -ForegroundColor DarkGray
            Write-Host "[$($f.Status)]" -NoNewline -ForegroundColor $color
            Write-Host " $($f.File)" -ForegroundColor White
            $i++
        }

        Write-Host ""
        Write-Host "  a) Review all files (step through diffs)" -ForegroundColor Magenta
        Write-Host "  o) Open all source files in VS Code" -ForegroundColor Magenta
        Write-Host "  m) Make a plan from this commit" -ForegroundColor Magenta
        Write-Host "  s) Show full commit summary" -ForegroundColor Magenta
        Write-Host "  p) Create PR from this commit" -ForegroundColor Magenta
        Write-Host "  q) Back to commit list" -ForegroundColor Magenta
        Write-Host ""

        $input = Read-Host "Select file (1-$($fileList.Count)), or a/o/m/s/p/q"

        if ($input -eq 'q' -or $input -eq '') { return }

        if ($input -eq 'a') {
            Write-Host "Opening diffs in VS Code (close each tab to advance)..." -ForegroundColor Yellow
            git -C $selected.Path difftool "$($selected.Hash)^..$($selected.Hash)"
            continue
        }

        if ($input -eq 'o') {
            [string[]]$filesToOpen = @($fileList | Where-Object { $_.RawStatus -ne 'D' } | ForEach-Object {
                Join-Path $selected.Path $_.File
            })
            if ($filesToOpen.Count -eq 0) {
                Write-Host "No source files to open (all deleted)." -ForegroundColor Red
            } else {
                Write-Host "Opening $($filesToOpen.Count) file(s) in VS Code..." -ForegroundColor Yellow
                & code $filesToOpen
            }
            continue
        }

        if ($input -eq 'm') {
            $fileListText = ($fileList | ForEach-Object { "- [$($_.Status)] $($_.File)" }) -join "`n"
            $planPrompt = @"
Review and improve the following commit:

Repo: $($selected.Repo)
Commit: $($selected.Hash)
Message: $($selected.Commit)

Changed files:
$fileListText
"@
            Write-Host "Launching MakePlan in background..." -ForegroundColor Yellow
            Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$PSScriptRoot\MakePlan.ps1`" -InitialPrompt `"$($planPrompt -replace '"', '\"')`""
            continue
        }

        if ($input -eq 's') {
            Write-Host ""
            git -C $selected.Path show $selected.Hash --stat
            Write-Host ""
            continue
        }

        if ($input -eq 'p') {
            # Derive branch name from commit message
            $sanitized = ($selected.Commit -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLower()
            $sanitized = $sanitized.Substring(0, [Math]::Min(50, $sanitized.Length))
            $branchName = "pr/$($selected.Hash.Substring(0,8))-$sanitized"

            # Get the default branch for the repo
            $defaultBranch = git -C $selected.Path rev-parse --abbrev-ref origin/HEAD 2>$null
            if ($defaultBranch) {
                $defaultBranch = $defaultBranch -replace '^origin/', ''
            } else {
                $defaultBranch = "main"
            }

            # Create a new branch at this commit
            Write-Host "Creating branch '$branchName'..." -ForegroundColor Yellow
            git -C $selected.Path branch $branchName $selected.Hash

            # Push the branch
            Write-Host "Pushing branch to origin..." -ForegroundColor Yellow
            git -C $selected.Path push -u origin $branchName

            # Create PR using gh
            Write-Host "Creating PR..." -ForegroundColor Yellow
            $repoUrl = git -C $selected.Path remote get-url origin
            $prUrl = gh pr create --repo $repoUrl --head $branchName --base $defaultBranch --title $selected.Commit --body "Created from commit $($selected.Hash)" --json url --jq '.url' 2>&1

            if ($LASTEXITCODE -eq 0 -and $prUrl) {
                Write-Host "PR created: $prUrl" -ForegroundColor Green
                Start-Process $prUrl
            } else {
                Write-Host "Failed to create PR: $prUrl" -ForegroundColor Red
                # Clean up: delete the remote branch and local branch
                git -C $selected.Path push origin --delete $branchName 2>$null
                git -C $selected.Path branch -D $branchName 2>$null
            }
            continue
        }

        $fileIdx = 0
        if ([int]::TryParse($input, [ref]$fileIdx)) {
            $fileIdx -= 1
            if ($fileIdx -lt 0 -or $fileIdx -ge $fileList.Count) {
                Write-Host "Invalid selection." -ForegroundColor Red
                continue
            }

            $file = $fileList[$fileIdx]

            if ($file.RawStatus -eq 'A') {
                # New file — just open it
                $fullPath = Join-Path $selected.Path $file.File
                Write-Host "New file — opening in VS Code..." -ForegroundColor Green
                code --wait $fullPath
            }
            elseif ($file.RawStatus -eq 'D') {
                # Deleted file — show what was removed
                $content = git -C $selected.Path show "$($selected.Hash)^:$($file.File)"
                $tempFile = Join-Path $env:TEMP "deleted_$(Split-Path $file.File -Leaf)"
                $content | Out-File -FilePath $tempFile -Encoding utf8
                Write-Host "Deleted file — opening previous version..." -ForegroundColor Red
                code --wait $tempFile
                Remove-Item $tempFile -ErrorAction SilentlyContinue
            }
            else {
                # Modified — show side-by-side diff in VS Code
                $beforeContent = git -C $selected.Path show "$($selected.Hash)^:$($file.File)"
                $afterContent = git -C $selected.Path show "$($selected.Hash):$($file.File)"

                $leaf = Split-Path $file.File -Leaf
                $beforeFile = Join-Path $env:TEMP "before_$leaf"
                $afterFile = Join-Path $env:TEMP "after_$leaf"

                $beforeContent | Out-File -FilePath $beforeFile -Encoding utf8
                $afterContent | Out-File -FilePath $afterFile -Encoding utf8

                Write-Host "Opening diff in VS Code..." -ForegroundColor Yellow
                code --wait --diff $beforeFile $afterFile
                Remove-Item $beforeFile, $afterFile -ErrorAction SilentlyContinue
            }
        }
        else {
            Write-Host "Invalid input." -ForegroundColor Red
        }
    }
}

# Main loop
while ($true) {
    Show-CommitList

    $selection = Read-Host "Select commit (1-$($commits.Count)), or press Enter to quit"
    if (-not $selection) { exit }

    $index = [int]$selection - 1
    if ($index -lt 0 -or $index -ge $commits.Count) {
        Write-Host "Invalid selection." -ForegroundColor Red
        continue
    }

    Review-Commit $commits[$index]
}
