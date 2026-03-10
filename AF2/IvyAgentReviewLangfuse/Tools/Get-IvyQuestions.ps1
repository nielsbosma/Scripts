<#
.SYNOPSIS
    Extracts all IvyQuestion requests and responses from langfuse data.
.PARAMETER LangfuseDir
    Path to the langfuse data folder.
.OUTPUTS
    Array of objects: TraceName, ObservationFile, Direction (Request/Response), Question, Success, AnswerLength, Error
#>
param(
    [Parameter(Mandatory)][string]$LangfuseDir
)

$traceFolders = Get-ChildItem -Path $LangfuseDir -Directory | Sort-Object Name
$results = @()

foreach ($traceFolder in $traceFolders) {
    $obsFiles = Get-ChildItem -Path $traceFolder.FullName -Filter "*.json" |
        Where-Object { $_.Name -ne "trace.json" } | Sort-Object Name

    foreach ($file in $obsFiles) {
        try {
            $json = Get-Content $file.FullName -Raw | ConvertFrom-Json
            $input = $json.input
            if (-not $input) { continue }

            $toolName = $input.toolName

            # Direct IvyQuestion event: input.question
            if ($input.question -and -not $toolName) {
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                    Direction = "Request"
                    Question = $input.question
                    Success = $null
                    AnswerLength = $null
                    Error = $null
                }
                continue
            }

            if ($toolName -ne 'IvyQuestion') { continue }

            # Request: input.request.question
            if ($input.request) {
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                    Direction = "Request"
                    Question = $input.request.question
                    Success = $null
                    AnswerLength = $null
                    Error = $null
                }
            }

            # Response: input.response
            if ($input.response) {
                $success = $input.response.success -eq $true
                $answerLen = $input.response.answerLength
                $error = $input.response.error
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                    Direction = "Response"
                    Question = $null
                    Success = $success
                    AnswerLength = $answerLen
                    Error = $error
                }
            }
        } catch {}
    }
}

return $results
