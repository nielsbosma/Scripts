<#
.SYNOPSIS
    Extracts all CSharpRefactoring events from langfuse data.
.PARAMETER LangfuseDir
    Path to the langfuse data folder.
.OUTPUTS
    Array of objects: Trace, Time, FilePath, Rules, RuleCount
#>
param(
    [Parameter(Mandatory)][string]$LangfuseDir
)

function Get-JsonString($obj, $prop) {
    if ($null -eq $obj) { return $null }
    $val = $obj.PSObject.Properties[$prop]
    if ($null -eq $val) { return $null }
    return [string]$val.Value
}

function Format-Time($iso) {
    if (-not $iso) { return "-" }
    try { return ([DateTimeOffset]::Parse($iso)).ToLocalTime().ToString("HH:mm:ss") } catch { return "-" }
}

$traceFolders = Get-ChildItem -Path $LangfuseDir -Directory | Sort-Object Name
$results = @()

foreach ($traceFolder in $traceFolders) {
    $obsFiles = Get-ChildItem -Path $traceFolder.FullName -Filter "*.json" |
        Where-Object { $_.Name -ne "trace.json" } | Sort-Object Name

    foreach ($file in $obsFiles) {
        try {
            $json = Get-Content $file.FullName -Raw | ConvertFrom-Json
            $obsName = Get-JsonString $json "name"
            if ($obsName -ne "CSharpRefactoring") { continue }

            $time = Format-Time (Get-JsonString $json "startTime")
            $filePath = $null
            $rules = @()

            if ($null -ne $json.metadata) {
                $filePath = Get-JsonString $json.metadata "FilePath"
                if ($null -ne $json.metadata.Rules) {
                    $rules = @($json.metadata.Rules)
                }
            }

            $results += [PSCustomObject]@{
                Trace     = $traceFolder.Name
                Time      = $time
                FilePath  = $filePath
                Rules     = ($rules -join ", ")
                RuleCount = $rules.Count
            }
        } catch {}
    }
}

return $results
