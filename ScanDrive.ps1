<# 
  Big/Recent File Hunter with Progress
  - Scans a path for files >= MinSizeMB modified in the last Days
  - Shows progress and a running tally
  - Outputs top N files and top directories by total size
  - Optional CSV export to Desktop
#>

param(
  [string]$Path = 'C:\',
  [int]$MinSizeMB = 100,
  [int]$Days = 3,
  [int]$Top = 200,
  [switch]$Csv,
  [string[]]$IncludeExt = @()   # e.g. @('.etl','.pml','.log')
)

# Quick heads-ups on usual suspects
try {
  $proc = Get-Process procmon -ErrorAction SilentlyContinue
  if ($proc) { Write-Warning "Procmon.exe is running (PID $($proc.Id)). It can produce huge .PML files." }
} catch {}

try {
  $etw = (logman query -ets) 2>$null
  if ($LASTEXITCODE -eq 0 -and $etw) {
    Write-Host "`nActive ETW sessions detected (logman):`n$etw`n" -ForegroundColor Yellow
  }
} catch {}

$Cutoff = (Get-Date).AddDays(-$Days)
$OutCsv = Join-Path $env:USERPROFILE ("Desktop\BigRecentFiles_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$SW = [System.Diagnostics.Stopwatch]::StartNew()
$matches = New-Object System.Collections.Generic.List[object]
$scanned = 0

Write-Host "Scanning $Path for files >= $MinSizeMB MB modified since $($Cutoff.ToString('yyyy-MM-dd HH:mm')) ..." -ForegroundColor Cyan

# Note: We keep progress indeterminate (no percent) to avoid the cost of pre-counting all files.
Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue |
ForEach-Object {
  $scanned++
  # Optional extension filter
  if ($IncludeExt.Count -gt 0) {
    if (-not ($IncludeExt -contains $_.Extension.ToLower())) { return }
  }
  if ($_.LastWriteTime -ge $Cutoff -and $_.Length -ge ($MinSizeMB * 1MB)) {
    $matches.Add([pscustomobject]@{
      SizeMB       = [math]::Round($_.Length / 1MB, 1)
      LastWriteTime= $_.LastWriteTime
      FullName     = $_.FullName
    })
  }
  if ($scanned % 1000 -eq 0) {
    Write-Progress -Activity "Scanning: $Path" -Status "Files scanned: $scanned | Matches: $($matches.Count) | Current: $($_.FullName)"
  }
}

$SW.Stop()
Write-Progress -Activity "Scanning: $Path" -Completed

$sorted = $matches | Sort-Object SizeMB -Descending
$topFiles = $sorted | Select-Object -First $Top

# Output: top files
Write-Host "`nTop $Top files (by size, MB):`n" -ForegroundColor Green
$topFiles | Format-Table -AutoSize

# Optional CSV
if ($Csv) {
  $topFiles | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
  Write-Host "`nSaved CSV to $OutCsv" -ForegroundColor Green
}

# Group by directory to spot runaway folders (e.g., logging dirs)
$topDirs =
  $matches |
  Group-Object { Split-Path $_.FullName -Parent } |
  ForEach-Object {
    [pscustomobject]@{
      Directory = $_.Name
      Files     = $_.Count
      TotalMB   = [math]::Round( ($_.Group | Measure-Object -Property SizeMB -Sum).Sum, 1)
      Latest    = ($_.Group | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    }
  } |
  Sort-Object TotalMB -Descending |
  Select-Object -First 20

Write-Host "`nTop 20 directories by total matched size (MB):`n" -ForegroundColor Green
$topDirs | Format-Table -AutoSize

Write-Host "`nDone in $([math]::Round($SW.Elapsed.TotalSeconds,1))s. Files scanned: $scanned. Matches: $($matches.Count)." -ForegroundColor Cyan
Write-Host "Tip: If you see huge .etl or .pml files still growing, consider:  logman query -ets  /  logman stop <name> -ets ; and close ProcMon." -ForegroundColor DarkYellow
