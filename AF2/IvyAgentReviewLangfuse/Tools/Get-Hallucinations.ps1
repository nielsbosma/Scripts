<#
.SYNOPSIS
    Extracts hallucination-relevant events: IvyQuestion Q&A, file writes, build results, and tool feedback.
    Used to correlate IvyQuestion answers with subsequent build failures.
.PARAMETER LangfuseDir
    Path to the langfuse data folder.
.OUTPUTS
    Array of objects: TraceName, ObservationFile, Time, EventType, Detail, IsError
    EventType: IvyQuestion-Q, IvyQuestion-A, WriteFile, Build, ToolFeedback
#>
param(
    [Parameter(Mandatory)][string]$LangfuseDir
)

function Format-Time($iso) {
    if (-not $iso) { return "-" }
    try { return ([DateTimeOffset]::Parse($iso)).ToLocalTime().ToString("HH:mm:ss") } catch { return "-" }
}

function Truncate($text, $max) {
    if (-not $text) { return "" }
    $collapsed = ($text -replace '\s+', ' ').Trim()
    if ($collapsed.Length -le $max) { return $collapsed }
    return $collapsed.Substring(0, $max - 3) + "..."
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

            $time = Format-Time $json.startTime
            $obsName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

            # Tool events - check both input (old) and metadata (new)
            $toolName = $null
            $toolRequest = $null
            $toolResponse = $null
            $toolFeedback = $null
            if ($input -and $input.toolName) {
                $toolName = $input.toolName
                $toolRequest = $input.request
                $toolResponse = $input.response
                $toolFeedback = $input.feedback
            } elseif ($json.metadata -and $json.metadata.toolName) {
                $toolName = $json.metadata.toolName
                $toolRequest = $json.metadata.request
                $toolResponse = $json.metadata.response
                $toolFeedback = $json.metadata.feedback
            }

            # IvyQuestion request (via toolName)
            if ($toolName -eq 'IvyQuestion' -and $toolRequest) {
                $q = $toolRequest.question
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = $obsName
                    Time = $time
                    EventType = "IvyQuestion-Q"
                    Detail = "Q: $(Truncate $q 120)"
                    IsError = $false
                }
                continue
            }

            # IvyQuestion request (direct event with question field, no toolName)
            $directQuestion = $null
            if ($input -and $input.question) { $directQuestion = $input.question }
            elseif ($json.metadata -and $json.metadata.question) { $directQuestion = $json.metadata.question }
            if ($directQuestion -and -not $toolName) {
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = $obsName
                    Time = $time
                    EventType = "IvyQuestion-Q"
                    Detail = "Q: $(Truncate $directQuestion 120)"
                    IsError = $false
                }
                continue
            }

            # IvyQuestion response
            if ($toolName -eq 'IvyQuestion' -and $toolResponse) {
                $success = $toolResponse.success -eq $true
                $answerLen = $toolResponse.answerLength
                $error = $toolResponse.error
                $detail = if ($success) { "A: ok ($answerLen chars)" } else { "A: FAIL $(Truncate $error 80)" }
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = $obsName
                    Time = $time
                    EventType = "IvyQuestion-A"
                    Detail = $detail
                    IsError = (-not $success)
                }
                continue
            }

            # ToolFeedback (direct format)
            if ($toolName -and $toolFeedback) {
                $results += [PSCustomObject]@{
                    TraceName = $traceFolder.Name
                    ObservationFile = $obsName
                    Time = $time
                    EventType = "ToolFeedback"
                    Detail = "${toolName}: $(Truncate $toolFeedback 100)"
                    IsError = $true
                }
                continue
            }

            # Message-based events - check both input.message (old) and metadata.message (new)
            $message = $null
            if ($input -and $input.message -and $input.message.'$type') {
                $message = $input.message
            } elseif ($json.metadata -and $json.metadata.message -and $json.metadata.message.'$type') {
                $message = $json.metadata.message
            }

            if (-not $message) { continue }
            $msgType = $message.'$type'

            switch ($msgType) {
                'WriteFileMessage' {
                    $results += [PSCustomObject]@{
                        TraceName = $traceFolder.Name
                        ObservationFile = $obsName
                        Time = $time
                        EventType = "WriteFile"
                        Detail = $message.filePath
                        IsError = $false
                    }
                }
                'WriteFileResultMessage' {
                    $success = $message.success -eq $true
                    if (-not $success) {
                        $results += [PSCustomObject]@{
                            TraceName = $traceFolder.Name
                            ObservationFile = $obsName
                            Time = $time
                            EventType = "WriteFile"
                            Detail = "[FAIL] $($message.filePath)"
                            IsError = $true
                        }
                    }
                }
                'BuildProjectResultMessage' {
                    $success = $message.success -eq $true
                    $detail = if ($success) { "OK" } else { "FAILED" }

                    if (-not $success -and $message.buildResults) {
                        $errorMsgs = @()
                        foreach ($br in $message.buildResults) {
                            if ($br.buildErrors) {
                                foreach ($err in $br.buildErrors) {
                                    $errorMsgs += "$($err.errorCode): $(Truncate $err.message 60)"
                                }
                            }
                        }
                        if ($errorMsgs.Count -gt 0) {
                            $detail += " " + ($errorMsgs[0..2] -join "; ")
                            if ($errorMsgs.Count -gt 3) { $detail += " (+$($errorMsgs.Count - 3) more)" }
                        }
                    }

                    $results += [PSCustomObject]@{
                        TraceName = $traceFolder.Name
                        ObservationFile = $obsName
                        Time = $time
                        EventType = "Build"
                        Detail = $detail
                        IsError = (-not $success)
                    }
                }
                'ToolFeedback' {
                    $fbTool = $message.toolName
                    $fb = $message.feedback
                    $results += [PSCustomObject]@{
                        TraceName = $traceFolder.Name
                        ObservationFile = $obsName
                        Time = $time
                        EventType = "ToolFeedback"
                        Detail = "${fbTool}: $(Truncate $fb 100)"
                        IsError = $true
                    }
                }
            }
        } catch {}
    }
}

return $results
