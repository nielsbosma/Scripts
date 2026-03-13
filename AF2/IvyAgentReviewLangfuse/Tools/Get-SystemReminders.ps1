<#
.SYNOPSIS
    Extracts all system reminder events fired by context window analysers from langfuse data.
.PARAMETER LangfuseDir
    Path to the langfuse data folder.
.OUTPUTS
    Array of objects: TraceName, ObservationFile, Time, Analyser, Message, NextObservationFile, NextActionPreview
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

function Truncate($text, $maxLen) {
    if ($null -eq $text) { return "" }
    if ($text.Length -le $maxLen) { return $text }
    return $text.Substring(0, $maxLen) + "..."
}

$traceFolders = Get-ChildItem -Path $LangfuseDir -Directory | Sort-Object Name
$results = @()

foreach ($traceFolder in $traceFolders) {
    $obsFiles = Get-ChildItem -Path $traceFolder.FullName -Filter "*.json" |
        Where-Object { $_.Name -ne "trace.json" } | Sort-Object Name

    # Load all observations for look-ahead
    $observations = @()
    foreach ($file in $obsFiles) {
        try {
            $json = Get-Content $file.FullName -Raw | ConvertFrom-Json
            $observations += [PSCustomObject]@{
                File = $file
                Json = $json
            }
        } catch {}
    }

    for ($i = 0; $i -lt $observations.Count; $i++) {
        $obs = $observations[$i]
        $json = $obs.Json

        # Detect AnalyserSystemReminder events
        $obsName = Get-JsonString $json "name"
        if ($obsName -ne "AnalyserSystemReminder") { continue }

        $time = Get-JsonString $json "startTime"

        # Extract metadata — data may be in .metadata or .input depending on Langfuse serialization
        $analyser = "unknown"
        $message = ""
        $metaAnalyser = if ($null -ne $json.metadata) { Get-JsonString $json.metadata "analyser" } else { $null }
        $inputAnalyser = if ($null -ne $json.input) { Get-JsonString $json.input "analyser" } else { $null }

        if ($metaAnalyser) {
            $analyser = $metaAnalyser
            $message = Get-JsonString $json.metadata "message"
            if (-not $message) { $message = "" }
        } elseif ($inputAnalyser) {
            $analyser = $inputAnalyser
            $message = Get-JsonString $json.input "message"
            if (-not $message) { $message = "" }
        }

        # Find next GENERATION observation
        $nextObsFile = ""
        $nextActionPreview = ""
        for ($j = $i + 1; $j -lt $observations.Count; $j++) {
            $nextJson = $observations[$j].Json
            $nextType = Get-JsonString $nextJson "type"
            if ($nextType -eq "GENERATION") {
                $nextObsFile = [System.IO.Path]::GetFileNameWithoutExtension($observations[$j].File.Name)

                # Try to extract tool calls from output
                if ($null -ne $nextJson.output) {
                    if ($null -ne $nextJson.output.content) {
                        $toolNames = @()
                        foreach ($item in $nextJson.output.content) {
                            $itemType = Get-JsonString $item "type"
                            if ($itemType -eq "tool_use") {
                                $toolNames += Get-JsonString $item "name"
                            }
                        }
                        if ($toolNames.Count -gt 0) {
                            $nextActionPreview = "Tool calls: " + ($toolNames -join ", ")
                        }
                    }
                    if (-not $nextActionPreview -and $null -ne $nextJson.output.tool_calls) {
                        $toolNames = @()
                        foreach ($call in $nextJson.output.tool_calls) {
                            if ($null -ne $call.function) {
                                $toolNames += Get-JsonString $call.function "name"
                            } else {
                                $toolNames += Get-JsonString $call "name"
                            }
                        }
                        if ($toolNames.Count -gt 0) {
                            $nextActionPreview = "Tool calls: " + ($toolNames -join ", ")
                        }
                    }
                }

                if (-not $nextActionPreview) {
                    $nextActionPreview = "?"
                }
                break
            }
        }

        $results += [PSCustomObject]@{
            TraceName         = $traceFolder.Name
            ObservationFile   = [System.IO.Path]::GetFileNameWithoutExtension($obs.File.Name)
            Time              = $time
            Analyser          = $analyser
            Message           = $message
            NextObservationFile = $nextObsFile
            NextActionPreview = $nextActionPreview
        }
    }
}

return $results
