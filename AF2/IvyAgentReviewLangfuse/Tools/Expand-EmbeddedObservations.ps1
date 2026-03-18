<#
.SYNOPSIS
    Extracts observations embedded in trace.json into separate JSON files.
.DESCRIPTION
    Some Langfuse sessions store all observations inside trace.json under the
    'observations' array, with no separate observation files. This tool extracts
    them so the other Get-*.ps1 tools can process them.
.PARAMETER LangfuseDir
    Path to the langfuse data folder (contains trace subfolders).
.OUTPUTS
    Number of observations extracted per trace folder.
#>
param(
    [Parameter(Mandatory)][string]$LangfuseDir
)

$traceFolders = Get-ChildItem -Path $LangfuseDir -Directory | Sort-Object Name

foreach ($traceFolder in $traceFolders) {
    $traceFile = Join-Path $traceFolder.FullName "trace.json"
    if (-not (Test-Path $traceFile)) { continue }

    # Check if separate observation files already exist
    $existingObs = Get-ChildItem -Path $traceFolder.FullName -Filter "*.json" |
        Where-Object { $_.Name -ne "trace.json" }
    if ($existingObs.Count -gt 0) {
        Write-Host "$($traceFolder.Name): $($existingObs.Count) observation files already exist, skipping"
        continue
    }

    $trace = Get-Content $traceFile -Raw | ConvertFrom-Json
    if (-not $trace.observations -or $trace.observations.Count -eq 0) {
        Write-Host "$($traceFolder.Name): no embedded observations"
        continue
    }

    $i = 1
    foreach ($obs in $trace.observations) {
        $type = if ($obs.type) { $obs.type.Substring(0, [Math]::Min(4, $obs.type.Length)) } else { "UNK" }
        $name = if ($obs.name) { ($obs.name -replace "[^a-zA-Z0-9_]","_") } else { "unnamed" }
        $name = $name.Substring(0, [Math]::Min(40, $name.Length))
        $filename = "{0:D3}_{1}_{2}.json" -f $i, $type, $name
        $obs | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $traceFolder.FullName $filename) -Encoding UTF8
        $i++
    }

    Write-Host "$($traceFolder.Name): extracted $($i - 1) observations"
}
