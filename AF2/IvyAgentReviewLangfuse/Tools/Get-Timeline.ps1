<#
.SYNOPSIS
    Produces a compact timeline of all observations across all traces in a langfuse session.
.PARAMETER LangfuseDir
    Path to the langfuse data folder (contains trace subfolders).
.PARAMETER Compact
    Omit UI noise events (UIStatus, UITokenUsage, UIChat, UICreditBalance, UILocalToolUse).
.OUTPUTS
    Array of objects: TraceFolder, TraceName, TraceLatency, Observations[]
    Each Observation: File, Time, Type, Workflow, Latency, Msgs, InputTokens, OutputTokens, CumulativeInput, Reason, Preview, IsError
#>
param(
    [Parameter(Mandatory)][string]$LangfuseDir,
    [switch]$Compact
)

$noiseTypes = @('UIStatusMessage','UITokenUsageMessage','UIChatMessage','UICreditBalanceMessage','UILocalToolUseMessage')

function Get-JsonString($element, $prop) {
    if ($element.PSObject.Properties.Name -contains $prop -and $null -ne $element.$prop) {
        return [string]$element.$prop
    }
    return $null
}

function Format-Time($iso) {
    if (-not $iso) { return "-" }
    try { return ([DateTimeOffset]::Parse($iso)).ToLocalTime().ToString("HH:mm:ss") } catch { return "-" }
}

function Truncate($text, $max) {
    if (-not $text) { return "-" }
    $collapsed = ($text -replace '\s+', ' ').Trim()
    if ($collapsed.Length -le $max) { return $collapsed }
    return $collapsed.Substring(0, $max - 3) + "..."
}

function Format-TokenCount($count) {
    if ($count -ge 1000000) { return "{0:F1}M" -f ($count / 1000000.0) }
    if ($count -ge 1000) { return "{0:F0}K" -f ($count / 1000.0) }
    return "$count"
}

function ShortPath($p) {
    if (-not $p) { return "?" }
    $name = [System.IO.Path]::GetFileName($p)
    if ($name) { return $name }
    return $p
}

$traceFolders = Get-ChildItem -Path $LangfuseDir -Directory | Sort-Object Name
$results = @()

foreach ($traceFolder in $traceFolders) {
    $traceName = $traceFolder.Name
    $traceLatency = $null
    $traceFile = Join-Path $traceFolder.FullName "trace.json"
    if (Test-Path $traceFile) {
        try {
            $tj = Get-Content $traceFile -Raw | ConvertFrom-Json
            if ($tj.latency) { $traceLatency = [math]::Round($tj.latency, 1) }
        } catch {}
    }

    $obsFiles = Get-ChildItem -Path $traceFolder.FullName -Filter "*.json" |
        Where-Object { $_.Name -ne "trace.json" } | Sort-Object Name

    $observations = @()
    $workflowStack = [System.Collections.Generic.Stack[string]]::new()
    $lastState = $null
    $cumulativeInput = 0

    foreach ($file in $obsFiles) {
        try {
            $json = Get-Content $file.FullName -Raw | ConvertFrom-Json
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

            # Workflow tracking
            $input = $json.input
            if ($input -and $input.message -and $input.message.'$type') {
                $msgType = $input.message.'$type'
                switch ($msgType) {
                    'WorkflowStartMessage' {
                        $wfName = Get-JsonString $input.message 'workflowName'
                        if ($wfName) { $workflowStack.Push($wfName); $lastState = $null }
                    }
                    'WorkflowTransitionMessage' {
                        $wfName = Get-JsonString $input.message 'workflowName'
                        if ($wfName -and ($workflowStack.Count -eq 0 -or $workflowStack.Peek() -ne $wfName)) {
                            $workflowStack.Push($wfName)
                        }
                        $lastState = $null
                    }
                    'WorkflowStateMessage' { $lastState = Get-JsonString $input.message 'stateName' }
                    { $_ -in 'WorkflowFinishedMessage','WorkflowFailedMessage' } {
                        if ($workflowStack.Count -gt 0) { $workflowStack.Pop() | Out-Null }
                        $lastState = $null
                    }
                }
            }

            $workflow = "-"
            if ($workflowStack.Count -gt 0) {
                $parts = @($workflowStack.ToArray())
                [array]::Reverse($parts)
                $workflow = $parts -join ">"
                if ($lastState) { $workflow += ":$lastState" }
            }

            $type = if ($json.type) { $json.type } else { "-" }
            $isGeneration = $type -eq "GENERATION"
            $time = Format-Time (Get-JsonString $json 'startTime')
            $latency = "-"; $msgs = "-"; $inputTok = 0; $outputTok = 0; $reason = "-"; $preview = "-"

            if ($isGeneration) {
                if ($json.latency) { $latency = "{0:F1}s" -f $json.latency }
                if ($json.input.messages) { $msgs = $json.input.messages.Count }
                elseif ($json.input -is [array]) { $msgs = $json.input.Count }
                if ($json.usageDetails) {
                    $inputTok = if ($json.usageDetails.input) { [long]$json.usageDetails.input } else { 0 }
                    $outputTok = if ($json.usageDetails.output) { [long]$json.usageDetails.output } else { 0 }
                }
                $cumulativeInput += $inputTok
                if ($json.metadata -and $json.metadata.finishReason) { $reason = $json.metadata.finishReason }

                # Preview from output
                if ($json.output) {
                    if ($json.output -is [array]) {
                        $toolNames = ($json.output | Where-Object { $_.name } | ForEach-Object { $_.name })
                        if ($toolNames) { $preview = $toolNames -join ", " }
                    } elseif ($json.output.toolCalls) {
                        $toolNames = ($json.output.toolCalls | Where-Object { $_.name } | ForEach-Object { $_.name })
                        $text = $json.output.text
                        if ($text -and $toolNames) { $preview = "$(Truncate $text 30) -> $($toolNames -join ', ')" }
                        elseif ($text) { $preview = Truncate $text 60 }
                        elseif ($toolNames) { $preview = $toolNames -join ", " }
                    } elseif ($json.output -is [string]) {
                        $preview = Truncate $json.output 60
                    }
                }
            } else {
                # Non-generation preview
                if ($input) {
                    $toolName = Get-JsonString $input 'toolName'
                    if ($toolName -and $input.feedback) {
                        $preview = "[!] ${toolName}: $(Truncate $input.feedback 40)"
                    } elseif ($toolName -and $input.response) {
                        $success = $input.response.success -eq $true
                        $preview = "${toolName}: $(if ($success) { 'ok' } else { 'fail' })"
                    } elseif ($toolName -and $input.request) {
                        $q = Get-JsonString $input.request 'question'
                        if (-not $q) { $q = Get-JsonString $input.request 'query' }
                        if (-not $q) { $q = Get-JsonString $input.request 'path' }
                        if ($q) { $preview = "${toolName}: $(Truncate $q 50)" }
                        else { $preview = $toolName }
                    } elseif ($input.message -and $input.message.'$type') {
                        $mt = $input.message.'$type'
                        $preview = switch ($mt) {
                            'WriteFileMessage' { "Write: $(ShortPath $input.message.filePath)" }
                            'ReadFileMessage' { "Read: $(ShortPath $input.message.filePath)" }
                            'BuildProjectResultMessage' {
                                $s = $input.message.success -eq $true
                                if ($s) { "Build: OK" } else { "Build: FAILED" }
                            }
                            'BashMessage' { "Bash: $(Truncate $input.message.command 50)" }
                            'WorkflowStartMessage' { "-> $(Get-JsonString $input.message 'workflowName')" }
                            'WorkflowFinishedMessage' { if ($input.message.success) { "[ok] finished" } else { "[FAIL] failed" } }
                            'WorkflowFailedMessage' { "[FAIL] $(Truncate (Get-JsonString $input.message 'prompt') 50)" }
                            'WorkflowStateMessage' { "State: $(Get-JsonString $input.message 'stateName')" }
                            'WorkflowReferenceMessage' { "Ref: $(Get-JsonString $input.message 'name')" }
                            'WorkflowReferenceResultMessage' {
                                $n = Get-JsonString $input.message 'name'
                                $s = $input.message.success -eq $true
                                if ($s -and $input.message.content) { "Ref: $n ($($input.message.content.Length) chars)" }
                                else { "Ref: $n $(if ($s) { '[ok]' } else { '[FAIL]' })" }
                            }
                            'ToolFeedback' { "[!] $(Get-JsonString $input.message 'toolName'): $(Truncate (Get-JsonString $input.message 'feedback') 40)" }
                            default { $mt }
                        }
                    }
                }
            }

            $isError = $preview -match '\[FAIL\]' -or $reason -eq 'HUNG' -or $reason -eq 'length'

            # Skip noise in compact mode
            if ($Compact -and -not $isGeneration -and $input.message -and $input.message.'$type' -in $noiseTypes) {
                if (-not ($input.feedback -or ($input.message -and $input.message.'$type' -eq 'ToolFeedback'))) {
                    continue
                }
            }

            $observations += [PSCustomObject]@{
                File = $fileName
                Time = $time
                Type = if ($isGeneration) { "GEN" } else { "SPAN" }
                Workflow = $workflow
                Latency = $latency
                Msgs = $msgs
                InputTokens = $inputTok
                OutputTokens = $outputTok
                CumulativeInput = Format-TokenCount $cumulativeInput
                Reason = $reason
                Preview = $preview
                IsError = $isError
            }
        } catch {
            $observations += [PSCustomObject]@{
                File = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                Time = "-"; Type = "ERR"; Workflow = "-"; Latency = "-"; Msgs = "-"
                InputTokens = 0; OutputTokens = 0; CumulativeInput = "-"
                Reason = "-"; Preview = "parse error: $_"; IsError = $true
            }
        }
    }

    $results += [PSCustomObject]@{
        TraceFolder = $traceFolder.FullName
        TraceName = $traceName
        TraceLatency = $traceLatency
        Observations = $observations
    }
}

return $results
