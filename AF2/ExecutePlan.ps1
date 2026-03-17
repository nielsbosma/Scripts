<#
.SYNOPSIS
    Executes a plan file with Claude Code in the appropriate working directory.

.DESCRIPTION
    Parses the plan filename to determine the queue name and maps it to a
    working directory, then runs Claude Code with the plan content.

.PARAMETER PlanFile
    Full path to the .md plan file to execute.

.EXAMPLE
    .\ExecutePlan.ps1 "D:\Repos\_Ivy\.plans\205-IvyFramework-AddFeature.md"
#>

param(
    [Parameter(Mandatory)]
    [string]$PlanFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Queue name → working directory ──────────────────────────────────────────
$QueueDirs = @{
    "IvyAgent"     = "D:\Repos\_Ivy\Ivy-Agent"
    "IvyConsole"   = "D:\Repos\_Ivy\Ivy"
    "IvyFramework" = "D:\Repos\_Ivy\Ivy-Framework"
    "IvyMcp"       = "D:\Repos\_Ivy\Ivy-Mcp"
}
$DefaultDir = "D:\Repos\_Ivy"

# ── Resolve plan file ───────────────────────────────────────────────────────
if (-not (Test-Path $PlanFile)) {
    Write-Host "Error: Plan file not found: $PlanFile" -ForegroundColor Red
    return
}

$fileName = [IO.Path]::GetFileName($PlanFile)
$stem     = [IO.Path]::GetFileNameWithoutExtension($PlanFile)

# Parse queue name from filename (second segment: "205-IvyFramework-Desc.md" → "IvyFramework")
$parts = $stem -split '-', 3
$queueName = if ($parts.Count -ge 2) { $parts[1] } else { "Default" }

# Map queue to working directory
$workDir = if ($QueueDirs.ContainsKey($queueName)) { $QueueDirs[$queueName] } else { $DefaultDir }

# ── Set terminal title ──────────────────────────────────────────────────────
$Host.UI.RawUI.WindowTitle = "Plan: $stem"

# ── Read and prepare content ────────────────────────────────────────────────
$content = Get-Content $PlanFile -Raw

# Strip YAML frontmatter so --- isn't parsed as a CLI flag
$content = $content -replace '(?s)\A---\r?\n.*?\r?\n---\r?\n', ''

# ── Execute ─────────────────────────────────────────────────────────────────
Write-Host "Plan:      $fileName" -ForegroundColor Cyan
Write-Host "Queue:     $queueName" -ForegroundColor Cyan
Write-Host "Directory: $workDir" -ForegroundColor Cyan
Write-Host ("-" * 60) -ForegroundColor DarkGray

Set-Location $workDir

# Allow nested Claude invocations
$env:CLAUDECODE = $null

& claude -p $content --dangerously-skip-permissions
if ($LASTEXITCODE -ne 0) {
    Write-Host "`nClaude exited with code $LASTEXITCODE" -ForegroundColor Red
} else {
    Write-Host "`nPlan execution completed successfully." -ForegroundColor Green
}
