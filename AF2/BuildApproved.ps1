#Requires -Version 7.0
<#
.SYNOPSIS
    Monitors approved plan files and executes them via Claude Code in parallel queues.
.DESCRIPTION
    Watches D:\Repos\_Ivy\.plans\approved for .md files.
    Groups by queue name (second filename segment) and runs items within each
    queue sequentially while running separate queues in parallel.
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
    [int]   $PollInterval = 3
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
foreach ($dir in @($WatchPath, $DonePath, $FailPath, $LogPath, $ReviewPath)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

# ── State ───────────────────────────────────────────────────────────────────
$seen    = [System.Collections.Generic.HashSet[string]]::new()
$queues  = @{}   # QueueName → List<string> of file paths
$active  = @{}   # QueueName → @{ Job; File; Start }
$history = [System.Collections.Generic.List[pscustomobject]]::new()

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

function Format-Duration([TimeSpan]$ts) {
    if ($ts.TotalHours -ge 1) { return "{0}h {1:00}m" -f [int]$ts.TotalHours, $ts.Minutes }
    return "{0}m {1:00}s" -f [int]$ts.TotalMinutes, $ts.Seconds
}

function Show-Status {
    # Build output as a single string buffer, then clear+write in one shot
    $buf = [System.Text.StringBuilder]::new()

    $null = $buf.AppendLine("")
    $null = $buf.AppendLine("  BuildApproved")
    $null = $buf.AppendLine("  $([string]::new([char]0x2500, 60))")
    $null = $buf.AppendLine("  Watching: $WatchPath")
    $null = $buf.AppendLine("")

    # Active
    if ($active.Count -gt 0) {
        $null = $buf.AppendLine("  RUNNING")
        foreach ($q in $active.Keys | Sort-Object) {
            $info    = $active[$q]
            $elapsed = Format-Duration ((Get-Date) - $info.Start)
            $name    = [IO.Path]::GetFileName($info.File)
            $null = $buf.AppendLine("    > $($q.PadRight(18))$($name.PadRight(46))$elapsed")
        }
        $null = $buf.AppendLine("")
    }

    # Pending
    $pendingQueues = @($queues.Keys | Where-Object { $queues[$_].Count -gt 0 } | Sort-Object)
    if ($pendingQueues.Count -gt 0) {
        $null = $buf.AppendLine("  PENDING")
        foreach ($q in $pendingQueues) {
            foreach ($f in $queues[$q]) {
                $name = [IO.Path]::GetFileName($f)
                $null = $buf.AppendLine("    - $($q.PadRight(18))$name")
            }
        }
        $null = $buf.AppendLine("")
    }

    # History (last 20)
    if ($history.Count -gt 0) {
        $null = $buf.AppendLine("  COMPLETED")
        $start = [Math]::Max(0, $history.Count - 20)
        for ($i = $start; $i -lt $history.Count; $i++) {
            $entry = $history[$i]
            $name  = [IO.Path]::GetFileName($entry.File)
            $dur   = Format-Duration $entry.Duration
            $icon  = if ($entry.Status -eq "Done") { "+" } else { "x" }
            $logName = [IO.Path]::GetFileName($entry.LogFile)
            $null = $buf.AppendLine("    $icon $($name.PadRight(56))[$dur]  $logName")
            if ($entry.Reason) {
                $null = $buf.AppendLine("      Reason: $($entry.Reason)")
            }
        }
        $null = $buf.AppendLine("")
    }

    # Summary
    $totalDone    = @($history | Where-Object Status -eq "Done").Count
    $totalFailed  = @($history | Where-Object Status -eq "Failed").Count
    $totalRunning = $active.Count
    $totalPending = ($queues.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
    $null = $buf.AppendLine("  Done: $totalDone  |  Failed: $totalFailed  |  Running: $totalRunning  |  Pending: $totalPending")

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

        # 2. Check completed jobs
        foreach ($q in @($active.Keys)) {
            $info = $active[$q]
            if ($info.Job.State -in @('Completed', 'Failed', 'Stopped')) {
                $output   = Receive-Job $info.Job 2>&1
                $success  = $info.Job.State -eq 'Completed'
                $duration = (Get-Date) - $info.Start
                Remove-Job $info.Job -Force

                # Write log
                $stem    = [IO.Path]::GetFileNameWithoutExtension($info.File)
                $logFile = Join-Path $LogPath "$stem.log"
                $outputStr = $output | Out-String
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

        # 3. Start next item for each idle queue
        foreach ($q in @($queues.Keys)) {
            if (-not $active.ContainsKey($q) -and $queues[$q].Count -gt 0) {
                $file    = $queues[$q][0]
                $queues[$q].RemoveAt(0)
                $workDir = Get-WorkDir $q

                $job = Start-Job -ScriptBlock {
                    param($PlanFile, $WorkDir, $ReviewDir)
                    Set-Location $WorkDir
                    $content = Get-Content $PlanFile -Raw
                    # Strip YAML frontmatter so --- isn't parsed as a CLI flag
                    $content = $content -replace '(?s)\A---\r?\n.*?\r?\n---\r?\n', ''
                    $stem = [IO.Path]::GetFileNameWithoutExtension($PlanFile)

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

                    & claude -p ($content + $reviewInstructions) --dangerously-skip-permissions 2>&1
                    if ($LASTEXITCODE -ne 0) { throw "claude exited with code $LASTEXITCODE" }
                } -ArgumentList $file, $workDir, $ReviewPath

                $active[$q] = @{
                    Job   = $job
                    File  = $file
                    Start = Get-Date
                }
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
    Write-Host "`nStopped. Cleaned up $($active.Count) active job(s)." -ForegroundColor Yellow
}
