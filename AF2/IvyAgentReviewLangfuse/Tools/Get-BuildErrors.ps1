<#
.SYNOPSIS
    Extracts all build attempts and their errors from langfuse data.
.PARAMETER LangfuseDir
    Path to the langfuse data folder.
.OUTPUTS
    Array of objects: TraceName, ObservationFile, BuildNumber, Success, Errors[], PrecedingWrites[]
    Each Error: RelativePath, ErrorCode, Line, Message
    Each PrecedingWrite: ObservationFile, FilePath
#>
param(
    [Parameter(Mandatory)][string]$LangfuseDir
)

$traceFolders = Get-ChildItem -Path $LangfuseDir -Directory | Sort-Object Name
$results = @()
$globalBuildNum = 0

foreach ($traceFolder in $traceFolders) {
    $obsFiles = Get-ChildItem -Path $traceFolder.FullName -Filter "*.json" |
        Where-Object { $_.Name -ne "trace.json" }

    # Pre-read all files and sort by startTime for correct chronological processing
    $obsParsed = @()
    foreach ($f in $obsFiles) {
        try {
            $j = Get-Content $f.FullName -Raw | ConvertFrom-Json
            $obsParsed += [PSCustomObject]@{ File = $f; Json = $j; StartTime = $j.startTime }
        } catch {}
    }
    $obsParsed = $obsParsed | Sort-Object StartTime

    $pendingWrites = @()

    foreach ($obs in $obsParsed) {
        try {
            $file = $obs.File
            $json = $obs.Json

            # Check both input.message (old format) and metadata.message (new format)
            $message = $null
            if ($json.input -and $json.input.message) {
                $message = $json.input.message
            } elseif ($json.metadata -and $json.metadata.message) {
                $message = $json.metadata.message
            }

            if (-not $message -or -not $message.'$type') { continue }

            $msgType = $message.'$type'

            if ($msgType -eq 'WriteFileMessage') {
                $pendingWrites += [PSCustomObject]@{
                    ObservationFile = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                    FilePath = $message.filePath
                }
            }
            elseif ($msgType -eq 'BuildProjectResultMessage') {
                $globalBuildNum++
                $success = $message.success -eq $true
                $errors = @()

                if (-not $success -and $message.buildResults) {
                    foreach ($br in $message.buildResults) {
                        $relPath = $br.relativePath
                        if ($br.buildErrors) {
                            foreach ($err in $br.buildErrors) {
                                $errors += [PSCustomObject]@{
                                    RelativePath = $relPath
                                    ErrorCode = $err.errorCode
                                    Line = $err.line
                                    Message = $err.message
                                }
                            }
                        }
                    }
                }

                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                    BuildNumber = $globalBuildNum
                    Success = $success
                    Errors = $errors
                    PrecedingWrites = $pendingWrites
                }

                $pendingWrites = @()
            }
        } catch {}
    }
}

return $results
