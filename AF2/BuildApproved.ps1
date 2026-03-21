#Requires -Version 7.0
<#
.SYNOPSIS
    Monitors approved plan files and executes them via Claude Code in parallel queues.
.DESCRIPTION
    Watches D:\Repos\_Ivy\.plans\approved for .md files.
    Groups by queue name (second filename segment) and runs items within each
    queue sequentially while running separate queues in parallel.
    Also watches D:\Repos\_Ivy\.plans\plan for task descriptions and sends them
    to MakePlan.ps1 for plan generation.
.EXAMPLE
    .\BuildApproved.ps1
    .\BuildApproved.ps1 -PollInterval 5
#>

param(
    [string]$WatchPath    = "D:\Repos\_Ivy\.plans\approved",
    [string]$DonePath     = "D:\Repos\_Ivy\.plans\completed",
    [string]$FailPath     = "D:\Repos\_Ivy\.plans\failed",
    [string]$LogPath      = "D:\Repos\_Ivy\.plans\logs",
    [string]$ReviewPath   = "D:\Repos\_Ivy\.plans\review",
    [string]$PlanWatchPath = "D:\Repos\_Ivy\.plans\plan",
    [int]   $PollInterval = 3,
    [int]   $TimeoutMinutes = 30
)

# ── Queue name → working directory ──────────────────────────────────────────
$QueueDirs = @{
    "IvyAgent"     = "D:\Repos\_Ivy\Ivy-Agent"
    "IvyConsole"   = "D:\Repos\_Ivy\Ivy"
    "IvyFramework" = "D:\Repos\_Ivy\Ivy-Framework"
    "IvyMcp"       = "D:\Repos\_Ivy\Ivy-Mcp"
}
$DefaultDir = "D:\Repos\_Ivy"

# ── Ensure directories exist ────────────────────────────────────────────────
foreach ($dir in @($WatchPath, $DonePath, $FailPath, $LogPath, $ReviewPath, $PlanWatchPath)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

# ── State ───────────────────────────────────────────────────────────────────
$seen    = [System.Collections.Generic.HashSet[string]]::new()
$queues  = @{}   # QueueName → List<string> of file paths
$active  = @{}   # QueueName → @{ Job; File; Start }
$history = [System.Collections.Generic.List[pscustomobject]]::new()

# Plan queue state
$seenPlan  = [System.Collections.Generic.HashSet[string]]::new()
$planQueue = [System.Collections.Generic.List[string]]::new()
$activePlan = $null  # @{ Job; File; Start } or $null

# ── Helpers ─────────────────────────────────────────────────────────────────
function Get-QueueName([string]$FileName) {
    $parts = [IO.Path]::GetFileNameWithoutExtension($FileName) -split '-', 3
    if ($parts.Count -ge 2) { return $parts[1] }
    return "Default"
}

function Get-WorkDir([string]$QueueName) {
    if ($QueueDirs.ContainsKey($QueueName)) { return $QueueDirs[$QueueName] }
    return $DefaultDir
}

function ConvertFrom-StreamJson([string]$RawOutput) {
    $lines = $RawOutput -split "`n" | Where-Object { $_.Trim() -ne '' }
    $readable = [System.Text.StringBuilder]::new()
    foreach ($line in $lines) {
        try {
            $obj = $line | ConvertFrom-Json -ErrorAction Stop
            switch ($obj.type) {
                'assistant' {
                    if ($obj.message.content) {
                        foreach ($block in $obj.message.content) {
                            if ($block.type -eq 'text') {
                                $null = $readable.AppendLine($block.text)
                            }
                            elseif ($block.type -eq 'tool_use') {
                                $null = $readable.AppendLine("[Tool: $($block.name)]")
                            }
                        }
                    }
                }
                'result' {
                    if ($obj.result) { $null = $readable.AppendLine($obj.result) }
                }
            }
        } catch {
            $null = $readable.AppendLine($line)
        }
    }
    return $readable.ToString()
}

function Format-Duration([TimeSpan]$ts) {
    if ($ts.TotalHours -ge 1) { return "{0}h {1:00}m" -f [int]$ts.TotalHours, $ts.Minutes }
    return "{0}m {1:00}s" -f [int]$ts.TotalMinutes, $ts.Seconds
}

function Show-Status {
    # Build output as a single string buffer, then clear+write in one shot
    $buf = [System.Text.StringBuilder]::new()
    $rst = "`e[0m"
    $check = [char]0x2714
    $cross = [char]0x2718

    $null = $buf.AppendLine("")
    $null = $buf.AppendLine("  `e[1;36mBuildApproved$rst")
    $null = $buf.AppendLine("  `e[90m$([string]::new([char]0x2500, 60))$rst")
    $null = $buf.AppendLine("  `e[37mWatching: `e[97m$WatchPath `e[90m| `e[97m$PlanWatchPath$rst")
    $null = $buf.AppendLine("")

    # Active
    if ($active.Count -gt 0) {
        $null = $buf.AppendLine("  `e[1;33mRUNNING$rst")
        foreach ($q in $active.Keys | Sort-Object) {
            $info      = $active[$q]
            $elapsedTs = (Get-Date) - $info.Start
            $elapsed   = Format-Duration $elapsedTs
            $name      = [IO.Path]::GetFileName($info.File)
            $timeColor = if ($elapsedTs.TotalMinutes -ge ($TimeoutMinutes * 0.8)) { "`e[31m" } else { "`e[33m" }
            $null = $buf.AppendLine("    > `e[33m$($q.PadRight(18))`e[97m$($name.PadRight(46))${timeColor}$elapsed$rst")
        }
        if ($activePlan) {
            $elapsedTs = (Get-Date) - $activePlan.Start
            $elapsed   = Format-Duration $elapsedTs
            $name      = [IO.Path]::GetFileName($activePlan.File)
            $timeColor = if ($elapsedTs.TotalMinutes -ge ($TimeoutMinutes * 0.8)) { "`e[31m" } else { "`e[35m" }
            $null = $buf.AppendLine("    > `e[35mMakePlan          `e[97m$($name.PadRight(46))${timeColor}$elapsed$rst")
        }
        $null = $buf.AppendLine("")
    } elseif ($activePlan) {
        $null = $buf.AppendLine("  `e[1;33mRUNNING$rst")
        $elapsedTs = (Get-Date) - $activePlan.Start
        $elapsed   = Format-Duration $elapsedTs
        $name      = [IO.Path]::GetFileName($activePlan.File)
        $timeColor = if ($elapsedTs.TotalMinutes -ge ($TimeoutMinutes * 0.8)) { "`e[31m" } else { "`e[35m" }
        $null = $buf.AppendLine("    > `e[35mMakePlan          `e[97m$($name.PadRight(46))${timeColor}$elapsed$rst")
        $null = $buf.AppendLine("")
    }

    # Pending
    $pendingQueues = @($queues.Keys | Where-Object { $queues[$_].Count -gt 0 } | Sort-Object)
    if ($pendingQueues.Count -gt 0) {
        $null = $buf.AppendLine("  `e[1;34mPENDING$rst")
        foreach ($q in $pendingQueues) {
            foreach ($f in $queues[$q]) {
                $name = [IO.Path]::GetFileName($f)
                $null = $buf.AppendLine("    `e[34m- $($q.PadRight(18))$name$rst")
            }
        }
        if ($planQueue.Count -gt 0) {
            foreach ($f in $planQueue) {
                $name = [IO.Path]::GetFileName($f)
                $null = $buf.AppendLine("    `e[35m- MakePlan          $name$rst")
            }
        }
        $null = $buf.AppendLine("")
    } elseif ($planQueue.Count -gt 0) {
        $null = $buf.AppendLine("  `e[1;34mPENDING$rst")
        foreach ($f in $planQueue) {
            $name = [IO.Path]::GetFileName($f)
            $null = $buf.AppendLine("    `e[35m- MakePlan          $name$rst")
        }
        $null = $buf.AppendLine("")
    }

    # History (last 20)
    if ($history.Count -gt 0) {
        $null = $buf.AppendLine("  `e[1;32mCOMPLETED$rst")
        $start = [Math]::Max(0, $history.Count - 20)
        for ($i = $start; $i -lt $history.Count; $i++) {
            $entry = $history[$i]
            $name  = [IO.Path]::GetFileName($entry.File)
            $dur   = Format-Duration $entry.Duration
            $icon  = if ($entry.Status -eq "Done") { "`e[32m$check" } else { "`e[31m$cross" }
            $logName = [IO.Path]::GetFileName($entry.LogFile)
            $null = $buf.AppendLine("    $icon $($name.PadRight(56))`e[90m[$dur]  $logName$rst")
            if ($entry.Reason) {
                $null = $buf.AppendLine("      `e[31mReason: $($entry.Reason)$rst")
            }
        }
        $null = $buf.AppendLine("")
    }

    # Summary
    $totalDone    = @($history | Where-Object Status -eq "Done").Count
    $totalFailed  = @($history | Where-Object Status -eq "Failed").Count
    $totalRunning = $active.Count + $(if ($activePlan) { 1 } else { 0 })
    $totalPending = ($queues.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum + $planQueue.Count
    $failColor = if ($totalFailed -gt 0) { "`e[31m" } else { "`e[90m" }
    $null = $buf.AppendLine("  `e[32mDone: $totalDone$rst  |  ${failColor}Failed: $totalFailed$rst  |  `e[33mRunning: $totalRunning$rst  |  `e[34mPending: $totalPending$rst")

    # Set terminal tab title via ANSI OSC
    Write-Host "`e]0;BA $totalRunning/$totalPending/$totalDone`a" -NoNewline

    # Atomic screen update: clear then write buffer
    Clear-Host
    Write-Host $buf.ToString()
}

# ── Main ────────────────────────────────────────────────────────────────────
Clear-Host
[Console]::CursorVisible = $false

# Verify claude is available
$claudePath = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudePath) {
    [Console]::CursorVisible = $true
    Write-Host "Error: 'claude' not found in PATH" -ForegroundColor Red
    exit 1
}

try {
    while ($true) {
        # 1. Scan for new files
        $files = Get-ChildItem $WatchPath -Filter "*.md" -File -ErrorAction SilentlyContinue |
                 Sort-Object Name

        foreach ($f in $files) {
            if ($seen.Add($f.Name)) {
                $q = Get-QueueName $f.Name
                if (-not $queues.ContainsKey($q)) {
                    $queues[$q] = [System.Collections.Generic.List[string]]::new()
                }
                $queues[$q].Add($f.FullName)
            }
        }

        # 1b. Scan for plan request files
        $planFiles = Get-ChildItem $PlanWatchPath -Filter "*.md" -File -ErrorAction SilentlyContinue |
                     Sort-Object Name
        foreach ($f in $planFiles) {
            if ($seenPlan.Add($f.Name)) {
                $planQueue.Add($f.FullName)
            }
        }

        # 2. Check completed jobs
        foreach ($q in @($active.Keys)) {
            $info = $active[$q]
            if ($info.Job.State -in @('Completed', 'Failed', 'Stopped')) {
                $output   = Receive-Job $info.Job 2>&1
                $success  = $info.Job.State -eq 'Completed'
                $duration = (Get-Date) - $info.Start
                Remove-Job $info.Job -Force

                # Write log (parse stream-json to readable text)
                $stem    = [IO.Path]::GetFileNameWithoutExtension($info.File)
                $logFile = Join-Path $LogPath "$stem.log"
                $rawStr = $output | Out-String
                $outputStr = ConvertFrom-StreamJson $rawStr
                $outputStr | Set-Content $logFile -Encoding utf8

                # Extract failure reason from last non-blank lines of output
                $reason = $null
                if (-not $success) {
                    $lines = $outputStr -split "`n" |
                             ForEach-Object { $_.Trim() } |
                             Where-Object { $_ -ne '' }
                    if ($lines.Count -gt 0) {
                        $reason = ($lines | Select-Object -Last 3) -join ' | '
                        if ($reason.Length -gt 120) { $reason = $reason.Substring(0, 117) + '...' }
                    }
                }

                # Append failure reason to plan file before moving to failed
                if (-not $success -and $reason -and (Test-Path $info.File)) {
                    $failureNote = "`n`n## Failed`n`n$reason`n"
                    Add-Content -Path $info.File -Value $failureNote -Encoding utf8
                }

                # Move plan file
                $destDir  = if ($success) { $DonePath } else { $FailPath }
                $fileName = [IO.Path]::GetFileName($info.File)
                if (Test-Path $info.File) {
                    Move-Item $info.File (Join-Path $destDir $fileName) -Force
                }

                $status = if ($success) { "Done" } else { "Failed" }
                $history.Add([pscustomobject]@{
                    File     = $info.File
                    Queue    = $q
                    Status   = $status
                    Duration = $duration
                    Reason   = $reason
                    LogFile  = $logFile
                })

                $active.Remove($q)
            }
        }

        # 2c. Check for timed-out jobs
        foreach ($q in @($active.Keys)) {
            $info = $active[$q]
            $elapsed = (Get-Date) - $info.Start
            if ($elapsed.TotalMinutes -ge $TimeoutMinutes) {
                # Force stop the hung job
                Stop-Job $info.Job -ErrorAction SilentlyContinue
                $output = Receive-Job $info.Job 2>&1
                Remove-Job $info.Job -Force

                # Write log (parse stream-json to readable text)
                $stem    = [IO.Path]::GetFileNameWithoutExtension($info.File)
                $logFile = Join-Path $LogPath "$stem.log"
                $rawStr = ($output | Out-String)
                $outputStr = (ConvertFrom-StreamJson $rawStr) + "`n`n--- TIMED OUT after $TimeoutMinutes minutes ---"
                $outputStr | Set-Content $logFile -Encoding utf8

                # Append timeout note to plan file
                $timeoutNote = "`n`n## Failed`n`nTimed out after $TimeoutMinutes minutes.`n"
                if (Test-Path $info.File) {
                    Add-Content -Path $info.File -Value $timeoutNote -Encoding utf8
                }

                # Move to failed
                $fileName = [IO.Path]::GetFileName($info.File)
                if (Test-Path $info.File) {
                    Move-Item $info.File (Join-Path $FailPath $fileName) -Force
                }

                $history.Add([pscustomobject]@{
                    File     = $info.File
                    Queue    = $q
                    Status   = "Failed"
                    Duration = $elapsed
                    Reason   = "Timed out after $TimeoutMinutes minutes"
                    LogFile  = $logFile
                })

                $active.Remove($q)
            }
        }

        # 2b. Check completed plan job
        if ($activePlan -and $activePlan.Job.State -in @('Completed', 'Failed', 'Stopped')) {
            $output   = Receive-Job $activePlan.Job 2>&1
            $success  = $activePlan.Job.State -eq 'Completed'
            $duration = (Get-Date) - $activePlan.Start
            Remove-Job $activePlan.Job -Force

            # Write log
            $stem    = [IO.Path]::GetFileNameWithoutExtension($activePlan.File)
            $logFile = Join-Path $LogPath "plan-$stem.log"
            ($output | Out-String) | Set-Content $logFile -Encoding utf8

            # Extract failure reason
            $reason = $null
            if (-not $success) {
                $lines = ($output | Out-String) -split "`n" |
                         ForEach-Object { $_.Trim() } |
                         Where-Object { $_ -ne '' }
                if ($lines.Count -gt 0) {
                    $reason = ($lines | Select-Object -Last 3) -join ' | '
                    if ($reason.Length -gt 120) { $reason = $reason.Substring(0, 117) + '...' }
                }
            }

            # Move or delete the plan request file
            $destDir = if ($success) { $DonePath } else { $FailPath }
            $fileName = [IO.Path]::GetFileName($activePlan.File)
            if (Test-Path $activePlan.File) {
                Move-Item $activePlan.File (Join-Path $destDir "plan-$fileName") -Force
            }

            $status = if ($success) { "Done" } else { "Failed" }
            $history.Add([pscustomobject]@{
                File     = $activePlan.File
                Queue    = "MakePlan"
                Status   = $status
                Duration = $duration
                Reason   = $reason
                LogFile  = $logFile
            })

            $activePlan = $null
        }

        # 2d. Check for timed-out plan job
        if ($activePlan) {
            $elapsed = (Get-Date) - $activePlan.Start
            if ($elapsed.TotalMinutes -ge $TimeoutMinutes) {
                Stop-Job $activePlan.Job -ErrorAction SilentlyContinue
                $output = Receive-Job $activePlan.Job 2>&1
                Remove-Job $activePlan.Job -Force

                $stem    = [IO.Path]::GetFileNameWithoutExtension($activePlan.File)
                $logFile = Join-Path $LogPath "plan-$stem.log"
                $outputStr = ($output | Out-String) + "`n`n--- TIMED OUT after $TimeoutMinutes minutes ---"
                $outputStr | Set-Content $logFile -Encoding utf8

                $fileName = [IO.Path]::GetFileName($activePlan.File)
                if (Test-Path $activePlan.File) {
                    Move-Item $activePlan.File (Join-Path $FailPath "plan-$fileName") -Force
                }

                $history.Add([pscustomobject]@{
                    File     = $activePlan.File
                    Queue    = "MakePlan"
                    Status   = "Failed"
                    Duration = $elapsed
                    Reason   = "Timed out after $TimeoutMinutes minutes"
                    LogFile  = $logFile
                })

                $activePlan = $null
            }
        }

        # 3. Start next item for each idle queue
        foreach ($q in @($queues.Keys)) {
            if (-not $active.ContainsKey($q) -and $queues[$q].Count -gt 0) {
                $file    = $queues[$q][0]
                $queues[$q].RemoveAt(0)
                $workDir = Get-WorkDir $q

                $job = Start-Job -ScriptBlock {
                    param($PlanFile, $WorkDir, $ReviewDir)
                    Set-Location $WorkDir
                    # Allow nested Claude invocations (e.g. IvyFeatureTester.ps1)
                    $env:CLAUDECODE = $null
                    $content = Get-Content $PlanFile -Raw
                    # Strip YAML frontmatter so --- isn't parsed as a CLI flag
                    $content = $content -replace '(?s)\A---\r?\n.*?\r?\n---\r?\n', ''
                    $stem = [IO.Path]::GetFileNameWithoutExtension($PlanFile)

                    $preCommitInstructions = @"

## Pre-Commit (REQUIRED)

Before creating any git commit, you MUST run the appropriate formatting/linting commands based on what files you changed.

**If you modified any frontend files** (files under ``src/frontend/`` — .ts, .tsx, .js, .jsx, .css files):

``````bash
cd src/frontend
npm run format
npm run lint:fix
cd ../..
``````

**If you modified any .cs (C#) files**:

``````bash
cd src
dotnet format
cd ..
``````

After running these commands, check the output for any remaining errors. If there are errors that were not auto-fixed (e.g., lint errors, type errors, or build failures), you MUST fix them in your code before proceeding. Re-run the commands after fixing to confirm they pass cleanly.

Once everything passes, stage any files that were reformatted or fixed (``git add`` the changed files), then proceed with the commit.
"@

                    $reviewInstructions = @"

## Review (optional)

After completing all steps above, decide if a human should manually review or test anything after this implementation. If so, create a file at:

    $ReviewDir\$stem.md

The file should contain a short, actionable checklist of what to verify. Examples:
- Test a specific command or feature end-to-end
- Run a sample app to confirm behavior
- Check UI rendering

If the change is purely mechanical (e.g., renaming, formatting, trivial config) and needs no human review, skip creating the file.
We don't need to review faq updates, doc fixes, or simple code changes that are low-risk.
"@

                    $ambiguityInstructions = @"

## Ambiguity Handling (REQUIRED)

You are running in non-interactive mode and CANNOT ask the user questions. If at any point you:
- Are unsure about the intended behavior or requirements
- Need clarification on scope, approach, or edge cases
- Encounter conflicting instructions in the plan
- Cannot find the files, functions, or patterns referenced in the plan
- Would normally ask a clarifying question before proceeding

Then you MUST stop immediately and fail with a clear message explaining:
1. What you were trying to do
2. What specific question(s) you need answered
3. What information was missing or ambiguous

Do NOT guess or make assumptions when uncertain. It is better to fail with a clear explanation than to silently produce incorrect work.
"@

                    & claude -p ($content + $preCommitInstructions + $reviewInstructions + $ambiguityInstructions) --dangerously-skip-permissions --output-format stream-json --verbose 2>&1
                    if ($LASTEXITCODE -ne 0) { throw "claude exited with code $LASTEXITCODE" }
                } -ArgumentList $file, $workDir, $ReviewPath

                $active[$q] = @{
                    Job   = $job
                    File  = $file
                    Start = Get-Date
                }
            }
        }

        # 3b. Start next plan job
        if (-not $activePlan -and $planQueue.Count -gt 0) {
            $file = $planQueue[0]
            $planQueue.RemoveAt(0)

            $job = Start-Job -ScriptBlock {
                param($PlanFile, $MakePlanScript)
                $content = Get-Content $PlanFile -Raw
                $env:CLAUDECODE = $null
                & pwsh -File $MakePlanScript $content 2>&1
                if ($LASTEXITCODE -ne 0) { throw "MakePlan exited with code $LASTEXITCODE" }
            } -ArgumentList $file, "D:\Repos\_Personal\Scripts\AF2\MakePlan.ps1"

            $activePlan = @{
                Job   = $job
                File  = $file
                Start = Get-Date
            }
        }

        # 4. Display
        Show-Status
        Start-Sleep -Seconds $PollInterval
    }
}
finally {
    [Console]::CursorVisible = $true
    foreach ($q in @($active.Keys)) {
        Stop-Job  $active[$q].Job -ErrorAction SilentlyContinue
        Remove-Job $active[$q].Job -Force -ErrorAction SilentlyContinue
    }
    if ($activePlan) {
        Stop-Job  $activePlan.Job -ErrorAction SilentlyContinue
        Remove-Job $activePlan.Job -Force -ErrorAction SilentlyContinue
    }
    $cleanedUp = $active.Count + $(if ($activePlan) { 1 } else { 0 })
    Write-Host "`nStopped. Cleaned up $cleanedUp active job(s)." -ForegroundColor Yellow
}
