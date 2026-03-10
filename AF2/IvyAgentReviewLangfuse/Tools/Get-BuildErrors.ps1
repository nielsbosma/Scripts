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
        Where-Object { $_.Name -ne "trace.json" } | Sort-Object Name

    $pendingWrites = @()

    foreach ($file in $obsFiles) {
        try {
            $json = Get-Content $file.FullName -Raw | ConvertFrom-Json
            $input = $json.input
            if (-not $input -or -not $input.message -or -not $input.message.'$type') { continue }

            $msgType = $input.message.'$type'

            if ($msgType -eq 'WriteFileMessage') {
                $pendingWrites += [PSCustomObject]@{
                    ObservationFile = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                    FilePath = $input.message.filePath
                }
            }
            elseif ($msgType -eq 'BuildProjectResultMessage') {
                $globalBuildNum++
                $success = $input.message.success -eq $true
                $errors = @()

                if (-not $success -and $input.message.buildResults) {
                    foreach ($br in $input.message.buildResults) {
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
