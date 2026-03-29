<#
.SYNOPSIS
    Determines the completion status of a langfuse session.
.DESCRIPTION
    Analyzes langfuse data to classify the session as one of:
    - Complete: All workflows finished, clean build, implementation present
    - Failed: Explicit error/timeout/generation failure in logs
    - PrematureStop: Agent stopped without error, incomplete implementation
.PARAMETER LangfuseDir
    Path to the langfuse data folder.
.OUTPUTS
    PSCustomObject with: Status, LastWorkflowState, LastObservationTime, LastObservationPreview,
    GenerationCount, HasUnfinishedWorkflows, HasGenerationFailure, StopReason
#>
param(
    [Parameter(Mandatory)][string]$LangfuseDir
)

function Format-Time($iso) {
    if (-not $iso) { return $null }
    try { return ([DateTimeOffset]::Parse($iso)).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss") } catch { return $null }
}

$traceFolders = Get-ChildItem -Path $LangfuseDir -Directory | Sort-Object Name

$generationCount = 0
$hasGenerationFailure = $false
$hasUnfinishedWorkflows = $false
$lastObsTime = $null
$lastObsPreview = $null
$lastWorkflowState = $null
$activeWorkflows = [System.Collections.Generic.Stack[string]]::new()
$finishedWorkflows = @()
$failedWorkflows = @()
$lastBuildSuccess = $null
$totalInputTokens = [long]0
$totalOutputTokens = [long]0
$hasTimeout = $false
$hasHungGeneration = $false
$stopReason = "Unknown"

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

    foreach ($obs in $obsParsed) {
        try {
            $file = $obs.File
            $json = $obs.Json

            $obsTime = Format-Time $json.startTime
            if ($obsTime) { $lastObsTime = $obsTime }

            if ($json.type -eq "GENERATION") {
                $generationCount++
                if ($json.usageDetails) {
                    if ($json.usageDetails.input) { $totalInputTokens += [long]$json.usageDetails.input }
                    if ($json.usageDetails.output) { $totalOutputTokens += [long]$json.usageDetails.output }
                }
                if ($json.metadata -and $json.metadata.finishReason) {
                    $reason = $json.metadata.finishReason
                    if ($reason -eq "HUNG") { $hasHungGeneration = $true }
                }
                # Check for generation output as preview
                if ($json.output) {
                    if ($json.output -is [array]) {
                        $toolNames = ($json.output | Where-Object { $_.name } | ForEach-Object { $_.name })
                        if ($toolNames) { $lastObsPreview = "GEN: $($toolNames -join ', ')" }
                    } elseif ($json.output.toolCalls) {
                        $toolNames = ($json.output.toolCalls | Where-Object { $_.name } | ForEach-Object { $_.name })
                        if ($toolNames) { $lastObsPreview = "GEN: $($toolNames -join ', ')" }
                    }
                }
                continue
            }

            # Message events
            $message = $null
            if ($json.input -and $json.input.message -and $json.input.message.'$type') {
                $message = $json.input.message
            } elseif ($json.metadata -and $json.metadata.message -and $json.metadata.message.'$type') {
                $message = $json.metadata.message
            }

            if ($message) {
                $msgType = $message.'$type'
                switch ($msgType) {
                    'WorkflowStartMessage' {
                        $wfName = $message.workflowName
                        if ($wfName) { $activeWorkflows.Push($wfName) }
                        $lastObsPreview = "WorkflowStart: $wfName"
                    }
                    'WorkflowStateMessage' {
                        $lastWorkflowState = $message.stateName
                        $lastObsPreview = "WorkflowState: $($message.stateName)"
                    }
                    'WorkflowFinishedMessage' {
                        if ($activeWorkflows.Count -gt 0) {
                            $wf = $activeWorkflows.Pop()
                            $finishedWorkflows += $wf
                        }
                        $lastWorkflowState = "Finished"
                        $lastObsPreview = "WorkflowFinished"
                    }
                    'WorkflowFailedMessage' {
                        if ($activeWorkflows.Count -gt 0) {
                            $wf = $activeWorkflows.Pop()
                            $failedWorkflows += $wf
                        }
                        $lastWorkflowState = "Failed"
                        $lastObsPreview = "WorkflowFailed"
                    }
                    'FailedMessage' {
                        $hasGenerationFailure = $true
                        $lastObsPreview = "GenerationFailure"
                    }
                    'BuildProjectResultMessage' {
                        $lastBuildSuccess = $message.success -eq $true
                        $lastObsPreview = "Build: $(if ($lastBuildSuccess) { 'OK' } else { 'FAILED' })"
                    }
                    'WriteFileMessage' {
                        $lastObsPreview = "WriteFile: $($message.filePath)"
                    }
                    default {
                        $lastObsPreview = $msgType
                    }
                }
            }

            # Tool events
            $toolName = $null
            if ($json.input -and $json.input.toolName) { $toolName = $json.input.toolName }
            elseif ($json.metadata -and $json.metadata.toolName) { $toolName = $json.metadata.toolName }
            if ($toolName) {
                $lastObsPreview = "Tool: $toolName"
            }
        } catch {}
    }
}

# Determine status
$hasUnfinishedWorkflows = $activeWorkflows.Count -gt 0
$status = "Unknown"

if ($failedWorkflows.Count -gt 0) {
    $status = "Failed"
    $stopReason = "Workflow failed: $($failedWorkflows -join ', ')"
} elseif ($hasGenerationFailure) {
    $status = "Failed"
    $stopReason = "Generation failure detected"
} elseif ($hasHungGeneration) {
    $status = "Failed"
    $stopReason = "Hung generation detected"
} elseif ($hasUnfinishedWorkflows) {
    $status = "PrematureStop"
    $stopReason = "Unfinished workflows: $($activeWorkflows.ToArray() -join ', ')"
} elseif ($generationCount -eq 0) {
    $status = "PrematureStop"
    $stopReason = "No generations found in langfuse data"
} elseif ($finishedWorkflows.Count -gt 0 -and -not $hasUnfinishedWorkflows) {
    $status = "Complete"
    $stopReason = "All workflows completed"
} else {
    # No workflow events at all — likely premature
    $status = "PrematureStop"
    $stopReason = "No workflow completion events found"
}

return [PSCustomObject]@{
    Status = $status
    LastWorkflowState = $lastWorkflowState
    LastObservationTime = $lastObsTime
    LastObservationPreview = $lastObsPreview
    GenerationCount = $generationCount
    TotalInputTokens = $totalInputTokens
    TotalOutputTokens = $totalOutputTokens
    HasUnfinishedWorkflows = $hasUnfinishedWorkflows
    HasGenerationFailure = $hasGenerationFailure
    ActiveWorkflows = @($activeWorkflows.ToArray())
    FinishedWorkflows = $finishedWorkflows
    FailedWorkflows = $failedWorkflows
    StopReason = $stopReason
}
