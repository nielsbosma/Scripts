<#
.SYNOPSIS
    Extracts all file write events from langfuse data.
.PARAMETER LangfuseDir
    Path to the langfuse data folder.
.OUTPUTS
    Array of objects: TraceName, ObservationFile, Time, FilePath, Success
#>
param(
    [Parameter(Mandatory)][string]$LangfuseDir
)

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

            # Check both input.message (old format) and metadata.message (new format)
            $message = $null
            if ($json.input -and $json.input.message) {
                $message = $json.input.message
            } elseif ($json.metadata -and $json.metadata.message) {
                $message = $json.metadata.message
            }

            if (-not $message -or -not $message.'$type') { continue }

            $msgType = $message.'$type'
            $time = Format-Time $json.startTime
            $obsName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

            if ($msgType -eq 'WriteFileMessage') {
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = $obsName
                    Time = $time
                    FilePath = $message.filePath
                    Success = $null
                }
            }
            elseif ($msgType -eq 'WriteFileResultMessage') {
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = $obsName
                    Time = $time
                    FilePath = $message.filePath
                    Success = ($message.success -eq $true)
                }
            }
        } catch {}
    }
}

return $results
