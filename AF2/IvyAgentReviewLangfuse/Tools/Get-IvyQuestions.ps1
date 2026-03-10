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
            if (-not $input) { continue }

            $toolName = $input.toolName
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

            # --- AnswerAgent SPAN: WebFetch questions answered by AnswerAgent ---
            if ($json.type -eq 'SPAN' -and $json.name -eq 'AnswerAgent' -and $input.question) {
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
                    Question = $input.question
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

            # --- Direct IvyQuestion event: input.question (no toolName) ---
            if ($input.question -and -not $toolName) {
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = $fileName
                    Direction = "Request"
                    Source = "IvyQuestion"
                    Question = $input.question
                    Success = $null
                    AnswerLength = $null
                    Error = $null
                }
                continue
            }

            if ($toolName -ne 'IvyQuestion') { continue }

            # --- IvyQuestion LocalResponse: request ---
            if ($input.request) {
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = $fileName
                    Direction = "Request"
                    Source = "IvyQuestion"
                    Question = $input.request.question
                    Success = $null
                    AnswerLength = $null
                    Error = $null
                }
            }

            # --- IvyQuestion LocalResponse: response ---
            if ($input.response) {
                $success = $input.response.success -eq $true
                $answerLen = $input.response.answerLength
                $error = $input.response.error
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = $fileName
                    Direction = "Response"
                    Source = "IvyQuestion"
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
