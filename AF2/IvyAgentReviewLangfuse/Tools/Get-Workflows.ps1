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
    $workflowStack = [System.Collections.Generic.Stack[string]]::new()
    $currentWorkflowName = $null
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

            $time = Format-Time $json.startTime
            $obsName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $msgType = $message.'$type'
            $msg = $message

            switch ($msgType) {
                'WorkflowStartMessage' {
                    if ($currentWorkflowName) { $workflowStack.Push($currentWorkflowName) }
                    $currentWorkflowName = $msg.workflowName
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
                    # Sub-workflows start via transition with a new workflowName
                    if ($msg.workflowName -and $msg.workflowName -ne $currentWorkflowName) {
                        if ($currentWorkflowName) { $workflowStack.Push($currentWorkflowName) }
                        $currentWorkflowName = $msg.workflowName
                    }
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
                        WorkflowName = $currentWorkflowName
                        StateName = $msg.stateName
                        ReferenceName = $null
                        ReferenceContent = $null
                        ReferenceChars = $null
                        Success = $null
                        Error = $null
                    }
                    # A "Finished" state in a sub-workflow means it completed — pop back to parent
                    if ($msg.stateName -eq "Finished" -and $workflowStack.Count -gt 0) {
                        $currentWorkflowName = $workflowStack.Pop()
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
                    $finishedName = $currentWorkflowName
                    if ($workflowStack.Count -gt 0) { $currentWorkflowName = $workflowStack.Pop() } else { $currentWorkflowName = $null }
                    $results += [PSCustomObject]@{
                        TraceName = $traceFolder.Name
                        ObservationFile = $obsName
                        Time = $time
                        EventType = "Finished"
                        WorkflowName = $finishedName
                        StateName = $null
                        ReferenceName = $null
                        ReferenceContent = $null
                        ReferenceChars = $null
                        Success = ($msg.success -eq $true)
                        Error = $null
                    }
                }
                'WorkflowFailedMessage' {
                    $failedName = $currentWorkflowName
                    if ($workflowStack.Count -gt 0) { $currentWorkflowName = $workflowStack.Pop() } else { $currentWorkflowName = $null }
                    $results += [PSCustomObject]@{
                        TraceName = $traceFolder.Name
                        ObservationFile = $obsName
                        Time = $time
                        EventType = "Failed"
                        WorkflowName = $failedName
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
