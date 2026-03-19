<#
.SYNOPSIS
    Extracts per-generation token usage data from Langfuse trace JSON files.

.DESCRIPTION
    Parses Langfuse generation JSON files to produce per-generation token analysis
    with cumulative totals, CSV export, and markdown report.

.PARAMETER LangfuseDir
    Path to the langfuse folder containing trace subfolders.

.PARAMETER OutputDir
    Path to write output files (CSV, report). Defaults to parent of LangfuseDir.

.EXAMPLE
    .\Get-PerGenerationTokens.ps1 -LangfuseDir "D:\Temp\ivy-agent\session\langfuse" -OutputDir "D:\output"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$LangfuseDir,

    [Parameter()]
    [string]$OutputDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $LangfuseDir)) {
    Write-Error "LangfuseDir not found: $LangfuseDir"
    return
}

if (-not $OutputDir) {
    $OutputDir = Split-Path $LangfuseDir -Parent
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Collect all generation JSON files across all trace folders
$traceFolders = Get-ChildItem -Path $LangfuseDir -Directory | Sort-Object Name
$generations = [System.Collections.ArrayList]::new()

foreach ($traceFolder in $traceFolders) {
    $genFiles = Get-ChildItem -Path $traceFolder.FullName -Filter "*_GENERATION_*.json" | Sort-Object Name
    foreach ($file in $genFiles) {
        $json = Get-Content $file.FullName -Raw | ConvertFrom-Json

        # Extract generation ID and agent name from filename pattern: NNN_GENERATION_AgentName.json
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $parts = $baseName -split '_GENERATION_'
        $genId = $parts[0]
        $agentName = if ($parts.Length -gt 1) { $parts[1] } else { 'Unknown' }

        $usage = if ($json.PSObject.Properties['usageDetails']) { $json.usageDetails } else { $null }
        $costDet = if ($json.PSObject.Properties['costDetails']) { $json.costDetails } else { $null }
        $inputTokens = if ($usage -and $usage.PSObject.Properties['input']) { [int]$usage.input } else { 0 }
        $outputTokens = if ($usage -and $usage.PSObject.Properties['output']) { [int]$usage.output } else { 0 }
        $cost = if ($costDet -and $costDet.PSObject.Properties['total']) { [decimal]$costDet.total } else { 0 }

        [void]$generations.Add([PSCustomObject]@{
            GenerationId   = $genId
            TraceName      = $traceFolder.Name
            AgentName      = $agentName
            Model          = $json.model
            InputTokens    = $inputTokens
            OutputTokens   = $outputTokens
            CumulativeInput  = 0
            CumulativeOutput = 0
            Cost           = $cost
            StartTime      = $json.startTime
            EndTime        = $json.endTime
            Preview        = try { if ($json.PSObject.Properties['output'] -and $json.output) { $clean = ($json.output -replace '\s+', ' '); $clean.Substring(0, [Math]::Min(80, $clean.Length)) } else { '' } } catch { '' }
        })
    }
}

# Calculate cumulative totals
$cumInput = 0
$cumOutput = 0
for ($i = 0; $i -lt $generations.Count; $i++) {
    $cumInput += $generations[$i].InputTokens
    $cumOutput += $generations[$i].OutputTokens
    $generations[$i].CumulativeInput = $cumInput
    $generations[$i].CumulativeOutput = $cumOutput
}

# Export main CSV
$csvPath = Join-Path $OutputDir "token-analysis.csv"
$generations | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "CSV exported: $csvPath"

# Export visualization CSV
$vizPath = Join-Path $OutputDir "token-visualization.csv"
$seqNum = 0
$generations | ForEach-Object {
    $seqNum++
    [PSCustomObject]@{
        Sequence        = $seqNum
        GenerationId    = $_.GenerationId
        TraceName       = $_.TraceName
        AgentName       = $_.AgentName
        InputTokens     = $_.InputTokens
        OutputTokens    = $_.OutputTokens
        CumulativeInput = $_.CumulativeInput
    }
} | Export-Csv -Path $vizPath -NoTypeInformation -Encoding UTF8
Write-Host "Visualization CSV exported: $vizPath"

# Statistics
$inputValues = $generations | ForEach-Object { $_.InputTokens }
$totalInput = ($inputValues | Measure-Object -Sum).Sum
$totalOutput = ($generations | ForEach-Object { $_.OutputTokens } | Measure-Object -Sum).Sum
$totalCost = ($generations | ForEach-Object { $_.Cost } | Measure-Object -Sum).Sum
$count = $generations.Count
$mean = [math]::Round($totalInput / $count, 0)
$sorted = $inputValues | Sort-Object
$median = if ($count % 2 -eq 0) {
    [math]::Round(($sorted[$count/2 - 1] + $sorted[$count/2]) / 2, 0)
} else {
    $sorted[[math]::Floor($count/2)]
}
$min = ($sorted | Select-Object -First 1)
$max = ($sorted | Select-Object -Last 1)

# Standard deviation
$sumSqDiff = 0
foreach ($v in $inputValues) { $sumSqDiff += [math]::Pow($v - $mean, 2) }
$stdDev = [math]::Round([math]::Sqrt($sumSqDiff / $count), 0)

# Top 10 most expensive
$top10 = $generations | Sort-Object -Property InputTokens -Descending | Select-Object -First 10

# First, middle, last generation tokens
$first = $generations[0]
$middle = $generations[[math]::Floor($count / 2)]
$last = $generations[$count - 1]

# Build report using array of lines to avoid interpolation issues
$lines = [System.Collections.ArrayList]::new()
$totalCostStr = [math]::Round($totalCost, 4).ToString()

[void]$lines.Add("# Token Analysis: Session b3f2e5f9")
[void]$lines.Add("")
[void]$lines.Add("## Summary")
[void]$lines.Add("- **Total Input:** $($totalInput.ToString('N0')) tokens")
[void]$lines.Add("- **Total Output:** $($totalOutput.ToString('N0')) tokens")
[void]$lines.Add("- **Total Cost:** $totalCostStr USD")
[void]$lines.Add("- **Generations:** $count")
[void]$lines.Add("- **Average Input:** $($mean.ToString('N0')) tokens/generation")
[void]$lines.Add("- **Average Output:** $([math]::Round($totalOutput / $count, 0).ToString('N0')) tokens/generation")
[void]$lines.Add("")
[void]$lines.Add("## Top 10 Most Expensive Generations")
[void]$lines.Add("")
[void]$lines.Add("| # | Seq | Trace | Agent | Input | Output | Cost | Cumulative Input |")
[void]$lines.Add("|---|-----|-------|-------|------:|-------:|-----:|-----------------:|")

$rank = 0
foreach ($g in $top10) {
    $rank++
    $seqIdx = $generations.IndexOf($g) + 1
    $costStr = [math]::Round($g.Cost, 4).ToString()
    [void]$lines.Add("| $rank | $seqIdx | $($g.TraceName) | $($g.AgentName) | $($g.InputTokens.ToString('N0')) | $($g.OutputTokens.ToString('N0')) | $costStr | $($g.CumulativeInput.ToString('N0')) |")
}

[void]$lines.Add("")
[void]$lines.Add("## Token Distribution")
[void]$lines.Add("- **Min:** $($min.ToString('N0')) tokens")
[void]$lines.Add("- **Max:** $($max.ToString('N0')) tokens")
[void]$lines.Add("- **Median:** $($median.ToString('N0')) tokens")
[void]$lines.Add("- **Mean:** $($mean.ToString('N0')) tokens")
[void]$lines.Add("- **Std Dev:** $($stdDev.ToString('N0')) tokens")
[void]$lines.Add("")
[void]$lines.Add("## Trend Analysis")
[void]$lines.Add("- **First generation** (Seq 1, $($first.TraceName)/$($first.GenerationId)): $($first.InputTokens.ToString('N0')) input tokens")
$midSeq = [math]::Floor($count / 2) + 1
[void]$lines.Add("- **Middle generation** (Seq $midSeq, $($middle.TraceName)/$($middle.GenerationId)): $($middle.InputTokens.ToString('N0')) input tokens")
[void]$lines.Add("- **Final generation** (Seq $count, $($last.TraceName)/$($last.GenerationId)): $($last.InputTokens.ToString('N0')) input tokens")
[void]$lines.Add("")
[void]$lines.Add("## Per-Generation Detail")
[void]$lines.Add("")
[void]$lines.Add("| Seq | Trace | ID | Agent | Input | Output | Cumulative In | Cost |")
[void]$lines.Add("|----:|-------|---:|-------|------:|-------:|--------------:|-----:|")

$seqNum = 0
foreach ($g in $generations) {
    $seqNum++
    $costStr = [math]::Round($g.Cost, 4).ToString()
    [void]$lines.Add("| $seqNum | $($g.TraceName) | $($g.GenerationId) | $($g.AgentName) | $($g.InputTokens.ToString('N0')) | $($g.OutputTokens.ToString('N0')) | $($g.CumulativeInput.ToString('N0')) | $costStr |")
}

# Determine pattern
$firstThird = $generations[0..([math]::Floor($count/3)-1)] | ForEach-Object { $_.InputTokens } | Measure-Object -Average
$lastThird = $generations[([math]::Floor(2*$count/3))..($count-1)] | ForEach-Object { $_.InputTokens } | Measure-Object -Average
$growthRatio = if ($firstThird.Average -gt 0) { [math]::Round($lastThird.Average / $firstThird.Average, 2) } else { 0 }

$pattern = if ($growthRatio -gt 1.5) { "Increasing (${growthRatio}x growth from first to last third)" }
           elseif ($growthRatio -lt 0.67) { "Decreasing (${growthRatio}x)" }
           else { "Relatively stable (${growthRatio}x ratio between first and last third)" }

[void]$lines.Add("")
[void]$lines.Add("## Growth Pattern")
$firstThirdAvg = [math]::Round($firstThird.Average, 0).ToString('N0')
$lastThirdAvg = [math]::Round($lastThird.Average, 0).ToString('N0')
[void]$lines.Add("- **First third avg:** $firstThirdAvg tokens")
[void]$lines.Add("- **Last third avg:** $lastThirdAvg tokens")
[void]$lines.Add("- **Growth ratio:** ${growthRatio}x")
[void]$lines.Add("- **Pattern:** $pattern")
[void]$lines.Add("")
[void]$lines.Add("## Observations")
[void]$lines.Add("")
[void]$lines.Add("### Context Accumulation")
[void]$lines.Add("Each generation within a trace includes the full conversation history, so input tokens grow as the conversation progresses. Cross-trace, context resets when a new AgentOrchestrator trace begins.")
[void]$lines.Add("")
[void]$lines.Add("### Build Error Recovery Cycles")
[void]$lines.Add("Trace 002 shows a pattern of build-fail-edit-rebuild cycles (generations at seq 14-35) where each retry adds the previous error context, compounding token usage.")
[void]$lines.Add("")
[void]$lines.Add("### Recommendations")
[void]$lines.Add("1. **Prompt caching** (already implemented in commit 1ee5f57) should significantly reduce effective input costs for repeated context")
[void]$lines.Add("2. **Build error context truncation** - Consider limiting build error output included in subsequent prompts")
[void]$lines.Add("3. **Conversation summarization** - For long traces, summarize earlier turns to prevent linear context growth")
[void]$lines.Add("4. **Type info caching** - GetTypeInfo results could be cached to avoid re-fetching and re-including in context")

$report = $lines -join "`n"

$reportPath = Join-Path $OutputDir "token-analysis-report.md"
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "Report exported: $reportPath"

# Output summary to console
Write-Host "`n=== Token Analysis Summary ==="
Write-Host "Generations: $count"
Write-Host "Total Input: $($totalInput.ToString('N0')) tokens"
Write-Host "Total Output: $($totalOutput.ToString('N0')) tokens"
Write-Host "Total Cost: `$`$([math]::Round($totalCost, 4))"
Write-Host "Mean Input: $($mean.ToString('N0')) | Median: $($median.ToString('N0')) | StdDev: $($stdDev.ToString('N0'))"
Write-Host "Min: $($min.ToString('N0')) | Max: $($max.ToString('N0'))"
Write-Host "Pattern: $pattern"
Write-Host "`nTop 5 most expensive:"
$rank = 0
foreach ($g in ($top10 | Select-Object -First 5)) {
    $rank++
    $seqIdx = $generations.IndexOf($g) + 1
    Write-Host "  $rank. Seq $seqIdx ($($g.TraceName)/$($g.GenerationId) $($g.AgentName)): $($g.InputTokens.ToString('N0')) input tokens"
}

# Return the generations for pipeline use
return $generations
