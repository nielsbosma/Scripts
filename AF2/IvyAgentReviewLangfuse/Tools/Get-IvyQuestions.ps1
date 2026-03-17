<#
.SYNOPSIS
    Extracts all IvyQuestion requests/responses AND AnswerAgent spans from langfuse data.
.PARAMETER LangfuseDir
    Path to the langfuse data folder.
.OUTPUTS
    Array of objects: TraceName, ObservationFile, Direction (Request/Response), Source (IvyQuestion/AnswerAgent), Question, Success, AnswerLength, Error
.NOTES
    Questions can arrive via two paths:
    1. IvyQuestion tool: EVENT__local__IvyQuestion (request) + EVENT_LocalResponse with toolName=IvyQuestion (response)
    2. WebFetch+AnswerAgent: SPAN_AnswerAgent with input.question/input.document and output.answer
    Only actual ToolFeedback events (name="ToolFeedback", input.feedback) represent validation errors.
    AnswerAgent spans should be classified by their own output, not confused with ToolFeedback.
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
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

            # Check both input (old) and metadata (new) for toolName
            $toolName = $null
            if ($input -and $input.toolName) {
                $toolName = $input.toolName
            } elseif ($json.metadata -and $json.metadata.toolName) {
                $toolName = $json.metadata.toolName
            }

            # --- AnswerAgent SPAN: WebFetch questions answered by AnswerAgent ---
            $question = if ($input) { $input.question } elseif ($json.metadata) { $json.metadata.question } else { $null }
            if ($json.type -eq 'SPAN' -and $json.name -eq 'AnswerAgent' -and $question) {
                $answer = $null
                $answerLen = $null
                $success = $false
                $err = $null

                if ($json.output -and $json.output.answer) {
                    $answer = $json.output.answer
                    $answerLen = $answer.Length
                    $success = $true
                } else {
                    $err = if ($json.level -eq 'ERROR') { "AnswerAgent error (level=ERROR)" } else { "No answer returned" }
                }

                # Request
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = $fileName
                    Direction = "Request"
                    Source = "AnswerAgent"
                    Question = $question
                    Success = $null
                    AnswerLength = $null
                    Error = $null
                }
                # Response
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = $fileName
                    Direction = "Response"
                    Source = "AnswerAgent"
                    Question = $null
                    Success = $success
                    AnswerLength = $answerLen
                    Error = $err
                }
                continue
            }

            # --- Direct IvyQuestion event: question field (no toolName) ---
            $directQuestion = $null
            if ($input -and $input.question) { $directQuestion = $input.question }
            elseif ($json.metadata -and $json.metadata.question) { $directQuestion = $json.metadata.question }
            if ($directQuestion -and -not $toolName) {
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = $fileName
                    Direction = "Request"
                    Source = "IvyQuestion"
                    Question = $directQuestion
                    Success = $null
                    AnswerLength = $null
                    Error = $null
                }
                continue
            }

            if ($toolName -ne 'IvyQuestion') { continue }

            # --- IvyQuestion LocalResponse: check both input (old) and metadata (new) ---
            $req = if ($input -and $input.request) { $input.request } elseif ($json.metadata -and $json.metadata.request) { $json.metadata.request } else { $null }
            $resp = if ($input -and $input.response) { $input.response } elseif ($json.metadata -and $json.metadata.response) { $json.metadata.response } else { $null }

            if ($req) {
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = $fileName
                    Direction = "Request"
                    Source = "IvyQuestion"
                    Question = $req.question
                    Success = $null
                    AnswerLength = $null
                    Error = $null
                }
            }

            if ($resp) {
                $success = $resp.success -eq $true
                $answerLen = $resp.answerLength
                $errMsg = $resp.error
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = $fileName
                    Direction = "Response"
                    Source = "IvyQuestion"
                    Question = $null
                    Success = $success
                    AnswerLength = $answerLen
                    Error = $errMsg
                }
            }
        } catch {}
    }
}

return $results
