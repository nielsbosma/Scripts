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
            $input = $json.input
            if (-not $input -or -not $input.message -or -not $input.message.'$type') { continue }

            $msgType = $input.message.'$type'
            $time = Format-Time $json.startTime
            $obsName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

            if ($msgType -eq 'WriteFileMessage') {
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = $obsName
                    Time = $time
                    FilePath = $input.message.filePath
                    Success = $null
                }
            }
            elseif ($msgType -eq 'WriteFileResultMessage') {
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = $obsName
                    Time = $time
                    FilePath = $input.message.filePath
                    Success = ($input.message.success -eq $true)
                }
            }
        } catch {}
    }
}

return $results
