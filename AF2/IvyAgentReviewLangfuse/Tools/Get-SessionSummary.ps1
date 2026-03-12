<#
.SYNOPSIS
    Produces aggregate summary statistics for a langfuse session.
.PARAMETER LangfuseDir
    Path to the langfuse data folder.
.PARAMETER TaskDescription
    Optional task description passed through to the one-shot scorer for complexity-adjusted scoring.
.OUTPUTS
    Single object with: TraceCount, GenerationCount, TotalInputTokens, TotalOutputTokens,
    IvyQuestionCount, IvyQuestionFailCount, IvyDocsCount, BuildAttempts, BuildFailures,
    WriteFileCount, UniqueFilesWritten, WorkflowNames, BashCount, ReadFileCount, GrepCount, GlobCount
#>
param(
    [Parameter(Mandatory)][string]$LangfuseDir,
    [string]$TaskDescription = ""
)

$traceFolders = Get-ChildItem -Path $LangfuseDir -Directory | Sort-Object Name

$stats = @{
    TraceCount = $traceFolders.Count
    GenerationCount = 0
    TotalInputTokens = [long]0
    TotalOutputTokens = [long]0
    IvyQuestionCount = 0
    IvyQuestionFailCount = 0
    IvyDocsCount = 0
    IvyDocsFailCount = 0
    BuildAttempts = 0
    BuildFailures = 0
    WriteFileCount = 0
    UniqueFilesWritten = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    WorkflowNames = [System.Collections.Generic.HashSet[string]]::new()
    BashCount = 0
    BashFailures = 0
    ReadFileCount = 0
    GrepCount = 0
    GlobCount = 0
    WebFetchCount = 0
    WebSearchCount = 0
    LspCount = 0
    ToolFeedbackCount = 0
    TotalCost = [decimal]0
}

foreach ($traceFolder in $traceFolders) {
    $obsFiles = Get-ChildItem -Path $traceFolder.FullName -Filter "*.json" |
        Where-Object { $_.Name -ne "trace.json" } | Sort-Object Name

    foreach ($file in $obsFiles) {
        try {
            $json = Get-Content $file.FullName -Raw | ConvertFrom-Json

            # Generation stats
            if ($json.type -eq "GENERATION") {
                $stats.GenerationCount++
                if ($json.usageDetails) {
                    if ($json.usageDetails.input) { $stats.TotalInputTokens += [long]$json.usageDetails.input }
                    if ($json.usageDetails.output) { $stats.TotalOutputTokens += [long]$json.usageDetails.output }
                }
                if ($json.costDetails -and $json.costDetails.total) {
                    $stats.TotalCost += [decimal]$json.costDetails.total
                } elseif ($json.calculatedTotalCost) {
                    $stats.TotalCost += [decimal]$json.calculatedTotalCost
                }
                continue
            }

            $input = $json.input
            if (-not $input) { continue }

            # Tool events
            $toolName = $input.toolName
            if ($toolName) {
                if ($input.feedback) { $stats.ToolFeedbackCount++ }
                if ($input.response) {
                    switch ($toolName) {
                        'IvyQuestion' {
                            $stats.IvyQuestionCount++
                            if ($input.response.success -eq $false) { $stats.IvyQuestionFailCount++ }
                        }
                        'IvyDocs' {
                            $stats.IvyDocsCount++
                            if ($input.response.success -eq $false) { $stats.IvyDocsFailCount++ }
                        }
                        'WebFetch' { $stats.WebFetchCount++ }
                        'WebSearch' { $stats.WebSearchCount++ }
                    }
                }
            }

            # Message events
            if ($input.message -and $input.message.'$type') {
                switch ($input.message.'$type') {
                    'BuildProjectResultMessage' {
                        $stats.BuildAttempts++
                        if ($input.message.success -ne $true) { $stats.BuildFailures++ }
                    }
                    'WriteFileMessage' {
                        $stats.WriteFileCount++
                        if ($input.message.filePath) { $stats.UniqueFilesWritten.Add($input.message.filePath) | Out-Null }
                    }
                    'ReadFileMessage' { $stats.ReadFileCount++ }
                    'BashMessage' { $stats.BashCount++ }
                    'BashResultMessage' { if ($input.message.success -ne $true) { $stats.BashFailures++ } }
                    'GrepMessage' { $stats.GrepCount++ }
                    'GlobMessage' { $stats.GlobCount++ }
                    'LspMessage' { $stats.LspCount++ }
                    'WorkflowStartMessage' { if ($input.message.workflowName) { $stats.WorkflowNames.Add($input.message.workflowName) | Out-Null } }
                    'ToolFeedback' { $stats.ToolFeedbackCount++ }
                }
            }
        } catch {}
    }
}

# Calculate OneShotScore via LLM judgement
$partialSummary = [PSCustomObject]@{
    GenerationCount = $stats.GenerationCount
    TotalInputTokens = $stats.TotalInputTokens
    TotalOutputTokens = $stats.TotalOutputTokens
    IvyQuestionCount = $stats.IvyQuestionCount
    IvyQuestionFailCount = $stats.IvyQuestionFailCount
    IvyDocsCount = $stats.IvyDocsCount
    IvyDocsFailCount = $stats.IvyDocsFailCount
    BuildAttempts = $stats.BuildAttempts
    BuildFailures = $stats.BuildFailures
    WriteFileCount = $stats.WriteFileCount
    UniqueFilesWritten = $stats.UniqueFilesWritten.Count
    BashCount = $stats.BashCount
    BashFailures = $stats.BashFailures
    ReadFileCount = $stats.ReadFileCount
    GrepCount = $stats.GrepCount
    GlobCount = $stats.GlobCount
    WebFetchCount = $stats.WebFetchCount
    WebSearchCount = $stats.WebSearchCount
    LspCount = $stats.LspCount
    ToolFeedbackCount = $stats.ToolFeedbackCount
    TotalCost = $stats.TotalCost
}
$oneShotScoreArgs = @{ Summary = $partialSummary }
if ($TaskDescription) { $oneShotScoreArgs.TaskDescription = $TaskDescription }
$oneShotScore = & "$PSScriptRoot\Get-OneShotScore.ps1" @oneShotScoreArgs

return [PSCustomObject]@{
    TraceCount = $stats.TraceCount
    GenerationCount = $stats.GenerationCount
    TotalInputTokens = $stats.TotalInputTokens
    TotalOutputTokens = $stats.TotalOutputTokens
    IvyQuestionCount = $stats.IvyQuestionCount
    IvyQuestionFailCount = $stats.IvyQuestionFailCount
    IvyDocsCount = $stats.IvyDocsCount
    IvyDocsFailCount = $stats.IvyDocsFailCount
    BuildAttempts = $stats.BuildAttempts
    BuildFailures = $stats.BuildFailures
    WriteFileCount = $stats.WriteFileCount
    UniqueFilesWritten = $stats.UniqueFilesWritten.Count
    WorkflowNames = @($stats.WorkflowNames)
    BashCount = $stats.BashCount
    BashFailures = $stats.BashFailures
    ReadFileCount = $stats.ReadFileCount
    GrepCount = $stats.GrepCount
    GlobCount = $stats.GlobCount
    WebFetchCount = $stats.WebFetchCount
    WebSearchCount = $stats.WebSearchCount
    LspCount = $stats.LspCount
    ToolFeedbackCount = $stats.ToolFeedbackCount
    TotalCost = $stats.TotalCost
    OneShotScore = $oneShotScore
}
