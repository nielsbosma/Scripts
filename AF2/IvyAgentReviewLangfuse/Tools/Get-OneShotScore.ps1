<#
.SYNOPSIS
    Uses an LLM to judge a session's one-shot quality score (1-10).
.PARAMETER Summary
    The summary object from Get-SessionSummary.ps1.
.PARAMETER TaskDescription
    Optional description of the task (e.g., "Pivot Table Builder - Drag-and-drop pivot table from uploaded CSV data")
    to help the LLM judge complexity-adjusted performance.
.OUTPUTS
    Integer score 1-10 (10 = perfect one-shot generation).
#>
param(
    [Parameter(Mandatory)][PSCustomObject]$Summary,
    [string]$TaskDescription = ""
)

. "$PSScriptRoot\..\..\..\_Shared.ps1"

# Compute derived ratios for the LLM
$buildFailureRate = if ($Summary.BuildAttempts -gt 0) { [math]::Round($Summary.BuildFailures / $Summary.BuildAttempts * 100) } else { 0 }
$bashFailureRate = if ($Summary.BashCount -gt 0) { [math]::Round($Summary.BashFailures / $Summary.BashCount * 100) } else { 0 }

$taskContext = if ($TaskDescription) { "`nTask description: $TaskDescription`nUse this to judge whether the session complexity (generations, builds, files) is reasonable for the task.`n" } else { "" }

$prompt = @"
You are evaluating an AI coding agent session. Score it from 1 to 10 on how well it performed as a "one-shot" execution (10 = perfect first attempt, 1 = completely failed).
$taskContext
Session statistics:
- Generations (LLM calls): $($Summary.GenerationCount)
- Build attempts: $($Summary.BuildAttempts)
- Build failures: $($Summary.BuildFailures) (failure rate: ${buildFailureRate}%)
- Tool feedback (corrections from system): $($Summary.ToolFeedbackCount)
- IvyQuestion calls: $($Summary.IvyQuestionCount) (failures: $($Summary.IvyQuestionFailCount))
- IvyDocs calls: $($Summary.IvyDocsCount) (failures: $($Summary.IvyDocsFailCount))
- Files written: $($Summary.WriteFileCount), Unique files: $($Summary.UniqueFilesWritten)
- Bash commands: $($Summary.BashCount) (failures: $($Summary.BashFailures), failure rate: ${bashFailureRate}%)
- Read file: $($Summary.ReadFileCount), Grep: $($Summary.GrepCount), Glob: $($Summary.GlobCount)
- Web fetch: $($Summary.WebFetchCount), Web search: $($Summary.WebSearchCount)
- LSP calls: $($Summary.LspCount)
- Total input tokens: $($Summary.TotalInputTokens)
- Total output tokens: $($Summary.TotalOutputTokens)

Scoring guidelines (use failure RATIOS, not absolute counts — a complex task with many builds is fine if the failure rate is low):
- 10: Zero build failures, zero tool feedback corrections. Clean execution.
- 8-9: At most 1 build failure or 1 correction. Low ratio of failures to total actions.
- 6-7: A few build failures or corrections, but reasonable for the task complexity. Build failure rate under 33%.
- 4-5: Build failure rate over 33%, or excessive iterations for a simple task, or multiple IvyQuestion failures.
- 2-3: More failures than successes, many tool feedback corrections, signs of being stuck in loops.
- 1: Complete failure — never produced working output, or nearly every action failed.

Important: Do NOT penalize high absolute counts (many generations, many builds) if the failure rate is low. A 52-generation session with 0 build failures is excellent. Focus on the ratio of failures to attempts.

Respond with ONLY a single integer from 1 to 10. Nothing else.
"@

$result = LlmComplete -Prompt $prompt

# Parse the integer from the response, fallback to 5 if parsing fails
$score = 5
if ($result -match '\b(\d+)\b') {
    $parsed = [int]$Matches[1]
    if ($parsed -ge 1 -and $parsed -le 10) {
        $score = $parsed
    }
}

return $score
