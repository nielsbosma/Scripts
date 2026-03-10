<#
.SYNOPSIS
    Extracts workflow events from langfuse data: starts, transitions, states, references, and completion.
.PARAMETER LangfuseDir
    Path to the langfuse data folder.
.OUTPUTS
    Array of objects: TraceName, ObservationFile, Time, EventType, WorkflowName, StateName, ReferenceName, ReferenceContent, Success, Error
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

            $time = Format-Time $json.startTime
            $obsName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $msgType = $input.message.'$type'
            $msg = $input.message

            switch ($msgType) {
                'WorkflowStartMessage' {
                    $results += [PSCustomObject]@{
                        TraceName = $traceFolder.Name
                        ObservationFile = $obsName
                        Time = $time
                        EventType = "Start"
                        WorkflowName = $msg.workflowName
                        StateName = $null
                        ReferenceName = $null
                        ReferenceContent = $null
                        ReferenceChars = $null
                        Success = $null
                        Error = $null
                    }
                }
                'WorkflowTransitionMessage' {
                    $results += [PSCustomObject]@{
                        TraceName = $traceFolder.Name
                        ObservationFile = $obsName
                        Time = $time
                        EventType = "Transition"
                        WorkflowName = $msg.workflowName
                        StateName = $null
                        ReferenceName = $null
                        ReferenceContent = $null
                        ReferenceChars = $null
                        Success = $null
                        Error = $null
                    }
                }
                'WorkflowStateMessage' {
                    $results += [PSCustomObject]@{
                        TraceName = $traceFolder.Name
                        ObservationFile = $obsName
                        Time = $time
                        EventType = "State"
                        WorkflowName = $null
                        StateName = $msg.stateName
                        ReferenceName = $null
                        ReferenceContent = $null
                        ReferenceChars = $null
                        Success = $null
                        Error = $null
                    }
                }
                'WorkflowReferenceMessage' {
                    $results += [PSCustomObject]@{
                        TraceName = $traceFolder.Name
                        ObservationFile = $obsName
                        Time = $time
                        EventType = "Reference"
                        WorkflowName = $null
                        StateName = $null
                        ReferenceName = $msg.name
                        ReferenceContent = $null
                        ReferenceChars = $null
                        Success = $null
                        Error = $null
                    }
                }
                'WorkflowReferenceResultMessage' {
                    $success = $msg.success -eq $true
                    $contentLen = if ($msg.content) { $msg.content.Length } else { $null }
                    $results += [PSCustomObject]@{
                        TraceName = $traceFolder.Name
                        ObservationFile = $obsName
                        Time = $time
                        EventType = "ReferenceResult"
                        WorkflowName = $null
                        StateName = $null
                        ReferenceName = $msg.name
                        ReferenceContent = $msg.content
                        ReferenceChars = $contentLen
                        Success = $success
                        Error = $msg.errorMessage
                    }
                }
                'WorkflowFinishedMessage' {
                    $results += [PSCustomObject]@{
                        TraceName = $traceFolder.Name
                        ObservationFile = $obsName
                        Time = $time
                        EventType = "Finished"
                        WorkflowName = $null
                        StateName = $null
                        ReferenceName = $null
                        ReferenceContent = $null
                        ReferenceChars = $null
                        Success = ($msg.success -eq $true)
                        Error = $null
                    }
                }
                'WorkflowFailedMessage' {
                    $results += [PSCustomObject]@{
                        TraceName = $traceFolder.Name
                        ObservationFile = $obsName
                        Time = $time
                        EventType = "Failed"
                        WorkflowName = $null
                        StateName = $null
                        ReferenceName = $null
                        ReferenceContent = $null
                        ReferenceChars = $null
                        Success = $false
                        Error = if ($msg.prompt) { $msg.prompt } else { $msg.error }
                    }
                }
            }
        } catch {}
    }
}

return $results
