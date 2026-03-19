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
    [string]$TaskDescription = "",
    [string]$IvyDir = ""
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
    HasGenerationFailure = $false
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

            # Tool events - check both input (old) and metadata (new)
            $toolName = $null
            $toolResponse = $null
            $toolFeedback = $null
            if ($input -and $input.toolName) {
                $toolName = $input.toolName
                $toolResponse = $input.response
                $toolFeedback = $input.feedback
            } elseif ($json.metadata -and $json.metadata.toolName) {
                $toolName = $json.metadata.toolName
                $toolResponse = $json.metadata.response
                $toolFeedback = $json.metadata.feedback
            }
            if ($toolName) {
                if ($toolFeedback) { $stats.ToolFeedbackCount++ }
                if ($toolResponse) {
                    switch ($toolName) {
                        'IvyQuestion' {
                            $stats.IvyQuestionCount++
                            if ($toolResponse.success -eq $false) { $stats.IvyQuestionFailCount++ }
                        }
                        'IvyDocs' {
                            $stats.IvyDocsCount++
                            if ($toolResponse.success -eq $false) { $stats.IvyDocsFailCount++ }
                        }
                        'WebFetch' { $stats.WebFetchCount++ }
                        'WebSearch' { $stats.WebSearchCount++ }
                    }
                }
            }

            # Message events - check both input.message (old) and metadata.message (new)
            $message = $null
            if ($input -and $input.message -and $input.message.'$type') {
                $message = $input.message
            } elseif ($json.metadata -and $json.metadata.message -and $json.metadata.message.'$type') {
                $message = $json.metadata.message
            }

            if ($message) {
                switch ($message.'$type') {
                    'BuildProjectResultMessage' {
                        $stats.BuildAttempts++
                        if ($message.success -ne $true) { $stats.BuildFailures++ }
                    }
                    'WriteFileMessage' {
                        $stats.WriteFileCount++
                        if ($message.filePath) { $stats.UniqueFilesWritten.Add($message.filePath) | Out-Null }
                    }
                    'ReadFileMessage' { $stats.ReadFileCount++ }
                    'BashMessage' { $stats.BashCount++ }
                    'BashResultMessage' { if ($message.success -ne $true) { $stats.BashFailures++ } }
                    'GrepMessage' { $stats.GrepCount++ }
                    'GlobMessage' { $stats.GlobCount++ }
                    'LspMessage' { $stats.LspCount++ }
                    'WorkflowStartMessage' { if ($message.workflowName) { $stats.WorkflowNames.Add($message.workflowName) | Out-Null } }
                    'ToolFeedback' { $stats.ToolFeedbackCount++ }
                    'FailedMessage' { $stats.HasGenerationFailure = $true }
                }
            }
        } catch {}
    }
}

# Parse review-spec.md for spec completion data
$specResults = $null
if ($IvyDir) {
    $reviewSpecPath = Join-Path $IvyDir "review-spec.md"
    if (Test-Path $reviewSpecPath) {
        $specContent = Get-Content $reviewSpecPath -Raw
        $implemented = 0; $partial = 0; $missing = 0
        # Count status markers in the review-spec tables
        $implemented = ([regex]::Matches($specContent, '✅\s*Implemented')).Count
        $partial = ([regex]::Matches($specContent, '⚠️\s*Partial')).Count
        $missing = ([regex]::Matches($specContent, '❌\s*Missing')).Count

        # Fallback: parse the summary table if markers weren't found
        if (($implemented + $partial + $missing) -eq 0) {
            $implMatch = [regex]::Match($specContent, 'Implemented\s*\|\s*(\d+)')
            $partMatch = [regex]::Match($specContent, 'Partial\s*\|\s*(\d+)')
            $missMatch = [regex]::Match($specContent, 'Missing\s*\|\s*(\d+)')
            if ($implMatch.Success) { $implemented = [int]$implMatch.Groups[1].Value }
            if ($partMatch.Success) { $partial = [int]$partMatch.Groups[1].Value }
            if ($missMatch.Success) { $missing = [int]$missMatch.Groups[1].Value }
        }

        if (($implemented + $partial + $missing) -gt 0) {
            $specResults = [PSCustomObject]@{
                Implemented = $implemented
                Partial = $partial
                Missing = $missing
                HasGenerationFailure = $stats.HasGenerationFailure
            }
        }
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
if ($specResults) { $oneShotScoreArgs.SpecResults = $specResults }
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
    HasGenerationFailure = $stats.HasGenerationFailure
    SpecImplemented = if ($specResults) { $specResults.Implemented } else { -1 }
    SpecPartial = if ($specResults) { $specResults.Partial } else { -1 }
    SpecMissing = if ($specResults) { $specResults.Missing } else { -1 }
}
