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
    [string]$TaskDescription = "",
    [PSCustomObject]$SpecResults = $null
)

. "$PSScriptRoot\..\..\..\_Shared.ps1"

# Compute derived ratios for the LLM
$buildFailureRate = if ($Summary.BuildAttempts -gt 0) { [math]::Round($Summary.BuildFailures / $Summary.BuildAttempts * 100) } else { 0 }
$bashFailureRate = if ($Summary.BashCount -gt 0) { [math]::Round($Summary.BashFailures / $Summary.BashCount * 100) } else { 0 }

$taskContext = if ($TaskDescription) { "`nTask description: $TaskDescription`nUse this to judge whether the session complexity (generations, builds, files) is reasonable for the task.`n" } else { "" }

$specContext = ""
if ($SpecResults) {
    $total = $SpecResults.Implemented + $SpecResults.Partial + $SpecResults.Missing
    $completionPct = if ($total -gt 0) { [math]::Round(($SpecResults.Implemented + $SpecResults.Partial * 0.5) / $total * 100) } else { 0 }
    $specContext = @"

Spec completion (from automated review of what the agent actually built vs what was requested):
- Requirements implemented: $($SpecResults.Implemented) of $total ($completionPct% complete)
- Partially implemented: $($SpecResults.Partial)
- Missing (not built at all): $($SpecResults.Missing)
- Session ended with generation failure: $($SpecResults.HasGenerationFailure)

"@
}

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
$specContext
Scoring guidelines:

CRITICAL: Spec completion is the MOST important factor. An agent that runs cleanly but delivers only half the requirements is NOT a good session. The score MUST reflect what was actually delivered.

Spec completion scoring (primary factor — overrides operational metrics):
- 10: 100% of requirements implemented, zero build failures, clean execution.
- 8-9: 90%+ requirements implemented, at most 1 build failure or correction.
- 6-7: 70-89% requirements implemented, reasonable failure rates.
- 4-5: 40-69% requirements implemented, OR build failure rate over 33%.
- 2-3: Under 40% requirements implemented, OR more failures than successes.
- 1: Complete failure — nothing implemented, or session crashed/failed entirely.

If spec completion data is not available, fall back to operational metrics only:
- Use failure RATIOS, not absolute counts — a complex task with many builds is fine if the failure rate is low.
- A 52-generation session with 0 build failures is excellent if it delivered results.

Additional penalties:
- If the session ended with a generation failure, cap the score at 5 maximum (the agent didn't finish).
- If there are missing requirements AND a generation failure, the score should be 1-3.

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
