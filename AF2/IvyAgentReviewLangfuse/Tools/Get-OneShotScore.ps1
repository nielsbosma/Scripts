<#
.SYNOPSIS
    Uses an LLM to judge a session's one-shot quality score (1-10).
.PARAMETER Summary
    The summary object from Get-SessionSummary.ps1.
.OUTPUTS
    Integer score 1-10 (10 = perfect one-shot generation).
#>
param(
    [Parameter(Mandatory)][PSCustomObject]$Summary
)

. "$PSScriptRoot\..\..\..\_Shared.ps1"

$prompt = @"
You are evaluating an AI coding agent session. Score it from 1 to 10 on how well it performed as a "one-shot" execution (10 = perfect first attempt, 1 = completely failed).

Session statistics:
- Generations (LLM calls): $($Summary.GenerationCount)
- Build attempts: $($Summary.BuildAttempts)
- Build failures: $($Summary.BuildFailures)
- Files written: $($Summary.WriteFileCount)
- Unique files written: $($Summary.UniqueFilesWritten)
- Tool feedback (corrections from system): $($Summary.ToolFeedbackCount)
- Bash commands: $($Summary.BashCount)
- Bash failures: $($Summary.BashFailures)
- IvyQuestion calls: $($Summary.IvyQuestionCount) (failures: $($Summary.IvyQuestionFailCount))
- IvyDocs calls: $($Summary.IvyDocsCount) (failures: $($Summary.IvyDocsFailCount))
- Read file: $($Summary.ReadFileCount), Grep: $($Summary.GrepCount), Glob: $($Summary.GlobCount)
- Web fetch: $($Summary.WebFetchCount), Web search: $($Summary.WebSearchCount)
- LSP calls: $($Summary.LspCount)
- Total input tokens: $($Summary.TotalInputTokens)
- Total output tokens: $($Summary.TotalOutputTokens)

Scoring guidelines:
- 10: Clean single-generation pass, no build failures, no corrections needed
- 7-9: Minor issues (1 retry, small corrections) but largely successful first attempt
- 4-6: Multiple retries or build failures, but eventually completed
- 1-3: Many failures, excessive retries, or signs of struggling

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
