<#
.SYNOPSIS
    Generates all formatted markdown reports from langfuse data.
.PARAMETER LangfuseDir
    Path to the langfuse data folder.
.PARAMETER OutputDir
    Path to output directory (e.g., WorkDir/.ivy/)
.PARAMETER SessionId
    Session ID for report headers
#>
param(
    [Parameter(Mandatory)][string]$LangfuseDir,
    [Parameter(Mandatory)][string]$OutputDir,
    [Parameter(Mandatory)][string]$SessionId
)

$toolsDir = Split-Path $PSCommandPath -Parent

# Helper to run tool and get objects
function Invoke-Tool($name) {
    & "$toolsDir\$name.ps1" -LangfuseDir $LangfuseDir
}

# 1. Timeline
Write-Host "Generating timeline..."
$timeline = Invoke-Tool "Get-Timeline"
$md = @"
# Session Timeline: $SessionId

"@
foreach ($trace in $timeline) {
    $latency = if ($trace.TraceLatency) { " ($($trace.TraceLatency)s)" } else { "" }
    $md += "`n## Trace: $($trace.TraceName)$latency`n`n"
    $md += "| # | Time | Type | Workflow | Preview |`n"
    $md += "|---|------|------|----------|---------|`n"
    foreach ($obs in $trace.Observations) {
        $icon = if ($obs.IsError) { "❌" } else { "" }
        $md += "| $($obs.File) | $($obs.Time) | $($obs.Type) | $($obs.Workflow) | $icon $($obs.Preview) |`n"
    }
}
$md | Out-File "$OutputDir\langfuse-timeline.md" -Encoding utf8

# 2. Hallucinations
Write-Host "Generating hallucinations..."
$hallucinations = Invoke-Tool "Get-Hallucinations"
$md = "# Hallucination Analysis: $SessionId`n`n"
if ($hallucinations.Count -eq 0) {
    $md += "No IvyQuestions found in this session.`n"
} else {
    $md += "## Event Timeline`n`n"
    $md += "| Time | Event | Detail |`n"
    $md += "|------|-------|--------|`n"
    foreach ($evt in $hallucinations) {
        $icon = if ($evt.IsError) { "❌" } else { "" }
        $md += "| $($evt.Time) | $($evt.EventType) | $icon $($evt.Detail) |`n"
    }
}
$md | Out-File "$OutputDir\langfuse-hallucinations.md" -Encoding utf8

# 3. Questions
Write-Host "Generating questions..."
$questions = Invoke-Tool "Get-IvyQuestions"
$md = "# IvyQuestion Log: $SessionId`n`n"
if ($questions.Count -eq 0) {
    $md += "No IvyQuestions asked during this session.`n"
} else {
    $md += "## Questions`n`n"
    $qNum = 1
    foreach ($q in $questions) {
        $status = if ($q.Success) { "✅ Success" } else { "❌ Failed" }
        $md += "### Q$qNum`: $($q.Question)`n`n"
        $md += "**Source**: $($q.Source)`n"
        $md += "**Status**: $status`n"
        if ($q.Success) {
            $md += "**Answer length**: $($q.AnswerLength) chars`n"
        } else {
            $md += "**Error**: $($q.Error)`n"
        }
        $md += "`n"
        $qNum++
    }
}
$md | Out-File "$OutputDir\langfuse-questions.md" -Encoding utf8

# 4. Workflows
Write-Host "Generating workflows..."
$workflows = Invoke-Tool "Get-Workflows"
$md = "# Workflows: $SessionId`n`n"
if ($workflows.Count -eq 0) {
    $md += "No workflow events found.`n"
} else {
    $workflowGroups = $workflows | Where-Object { $_.WorkflowName } | Group-Object WorkflowName
    foreach ($wf in $workflowGroups) {
        $events = $wf.Group
        $status = if ($events | Where-Object { $_.EventType -eq "Failed" }) { "❌ Failed" } elseif ($events | Where-Object { $_.EventType -eq "Finished" -and $_.Success }) { "✅ Success" } else { "🔄 Running" }

        $md += "## $($wf.Name)`n`n"
        $md += "**Status**: $status`n"

        $states = $events | Where-Object { $_.StateName } | Select-Object -ExpandProperty StateName -Unique
        if ($states) {
            $md += "**States**: $($states -join ' → ')`n"
        }

        if ($events[0].Error) {
            $md += "**Error**: $($events[0].Error)`n"
        }
        $md += "`n"
    }

    $md += "## Summary`n`n"
    $md += "| Workflow | Status | Transitions |`n"
    $md += "|----------|--------|-------------|`n"
    foreach ($wf in $workflowGroups) {
        $events = $wf.Group
        $status = if ($events | Where-Object { $_.EventType -eq "Failed" }) { "❌" } elseif ($events | Where-Object { $_.EventType -eq "Finished" -and $_.Success }) { "✅" } else { "🔄" }
        $transCount = ($events | Where-Object { $_.EventType -eq "Transition" }).Count
        $md += "| $($wf.Name) | $status | $transCount |`n"
    }
}
$md | Out-File "$OutputDir\langfuse-workflows.md" -Encoding utf8

# 5. Reference Connections
Write-Host "Generating reference connections..."
$refs = Invoke-Tool "Get-ReferenceConnections"
$md = "# Reference Connections: $SessionId`n`n"
if ($refs.Count -eq 0) {
    $md += "No reference connections used.`n"
} else {
    $md += "## Connections Used`n`n"
    $md += "| Connection | Local Path |`n"
    $md += "|------------|------------|`n"
    foreach ($ref in $refs | Select-Object -Unique Connection, LocalPath) {
        $md += "| $($ref.Connection) | ``$($ref.LocalPath)`` |`n"
    }
}
$md | Out-File "$OutputDir\langfuse-reference-connections.md" -Encoding utf8

# 6. Docs Read
Write-Host "Generating docs read..."
$docs = Invoke-Tool "Get-DocsRead"
$md = "# Docs Read: $SessionId`n`n"
if ($docs.Count -eq 0) {
    $md += "No IvyDocs read during this session.`n"
} else {
    $md += "## Documents`n`n"
    $md += "| # | Trace | Path | Status | Size |`n"
    $md += "|---|-------|------|--------|------|`n"
    $num = 1
    foreach ($doc in $docs) {
        $status = if ($doc.Success) { "✅" } else { "❌ $($doc.Error)" }
        $size = if ($doc.Success) { "$($doc.ContentLength) chars" } else { "" }
        $md += "| $num | $($doc.TraceName) | $($doc.Path) | $status | $size |`n"
        $num++
    }

    $successful = ($docs | Where-Object Success).Count
    $failed = ($docs | Where-Object { -not $_.Success }).Count
    $totalChars = ($docs | Where-Object Success | Measure-Object -Property ContentLength -Sum).Sum

    $md += "`n## Summary`n`n"
    $md += "| Metric | Count |`n"
    $md += "|--------|-------|`n"
    $md += "| Total doc reads | $($docs.Count) |`n"
    $md += "| Successful | $successful |`n"
    $md += "| Failed | $failed |`n"
    $md += "| Total chars read | $totalChars |`n"
}
$md | Out-File "$OutputDir\langfuse-docs.md" -Encoding utf8

# 7. Build Errors
Write-Host "Generating build errors..."
$builds = Invoke-Tool "Get-BuildErrors"
$md = "# Build Errors: $SessionId`n`n"
if ($builds.Count -eq 0) {
    $md += "No builds found.`n"
} else {
    foreach ($build in $builds) {
        $status = if ($build.Success) { "✅ OK" } else { "❌ FAILED" }
        $md += "## Build #$($build.BuildNumber) ($($build.ObservationFile)) — $status`n`n"

        if (-not $build.Success -and $build.Errors) {
            $errByFile = $build.Errors | Group-Object RelativePath
            foreach ($fileGroup in $errByFile) {
                $md += "### $($fileGroup.Name)`n"
                foreach ($err in $fileGroup.Group) {
                    $md += "- ``$($err.ErrorCode):$($err.Line)`` — $($err.Message)`n"
                }
                $md += "`n"
            }

            if ($build.PrecedingWrites) {
                $md += "**Preceding writes**:`n"
                foreach ($write in $build.PrecedingWrites) {
                    $md += "- ``$($write.FilePath)```n"
                }
                $md += "`n"
            }
        }
    }

    $failed = ($builds | Where-Object { -not $_.Success }).Count
    $errorCodes = $builds | Where-Object { -not $_.Success } | Select-Object -ExpandProperty Errors | Select-Object -ExpandProperty ErrorCode -Unique | Sort-Object

    $md += "## Summary`n`n"
    $md += "| Metric | Count |`n"
    $md += "|--------|-------|`n"
    $md += "| Total builds | $($builds.Count) |`n"
    $md += "| Failed builds | $failed |`n"
    $md += "| Unique error codes | $($errorCodes -join ', ') |`n"
}
$md | Out-File "$OutputDir\langfuse-build-errors.md" -Encoding utf8

# 8. GetTypeInfo
Write-Host "Generating GetTypeInfo usage..."
$typeInfo = Invoke-Tool "Get-TypeInfoUsage"
$md = "# GetTypeInfo Usage: $SessionId`n`n"
if ($typeInfo.Count -eq 0) {
    $md += "No GetTypeInfo calls found.`n"
} else {
    $md += "## Lookups`n`n"
    $num = 1
    foreach ($lookup in $typeInfo) {
        $status = if ($lookup.Success) { "✅ $($lookup.TotalMatches) matches" } else { "❌ Failed" }
        $md += "### Lookup $num`n`n"
        $md += "**Search**: ``$($lookup.Search)```n"
        $md += "**Type**: $($lookup.SearchType)`n"
        $md += "**Trace**: $($lookup.TraceName)`n"
        $md += "**Status**: $status`n"
        if ($lookup.Results) {
            $md += "**Results**: $($lookup.Results -join ', ')`n"
        }
        if ($lookup.Warning) {
            $md += "**Warning**: $($lookup.Warning)`n"
        }
        $md += "`n"
        $num++
    }

    # Patterns
    $repeated = $typeInfo | Group-Object Search | Where-Object { $_.Count -gt 1 }
    $failed = $typeInfo | Where-Object { -not $_.Success -or $_.TotalMatches -eq 0 }
    $methodSearches = $typeInfo | Where-Object { $_.SearchType -eq "Method" }

    if ($repeated -or $failed -or $methodSearches) {
        $md += "## Patterns`n`n"

        if ($repeated) {
            $md += "### Repeated Searches`n"
            foreach ($r in $repeated) {
                $md += "- ``$($r.Name)`` (x$($r.Count))`n"
            }
            $md += "`n"
        }

        if ($failed) {
            $md += "### Failed Lookups`n"
            foreach ($f in $failed) {
                $md += "- ``$($f.Search)```n"
            }
            $md += "`n"
        }

        if ($methodSearches) {
            $md += "### Method Searches`n"
            foreach ($m in $methodSearches) {
                $md += "- ``$($m.Search)```n"
            }
            $md += "`n"
        }
    }

    $successful = ($typeInfo | Where-Object Success).Count
    $failedCount = ($typeInfo | Where-Object { -not $_.Success -or $_.TotalMatches -eq 0 }).Count
    $uniqueSearches = ($typeInfo | Select-Object -ExpandProperty Search -Unique).Count
    $typeSearches = ($typeInfo | Where-Object { $_.SearchType -eq "Type" }).Count
    $methodSearchCount = $methodSearches.Count
    $repeatedCount = $repeated.Count

    $md += "## Summary`n`n"
    $md += "| Metric | Count |`n"
    $md += "|--------|-------|`n"
    $md += "| Total GetTypeInfo calls | $($typeInfo.Count) |`n"
    $md += "| Successful | $successful |`n"
    $md += "| Failed / 0 results | $failedCount |`n"
    $md += "| Unique search terms | $uniqueSearches |`n"
    $md += "| Type searches | $typeSearches |`n"
    $md += "| Method searches | $methodSearchCount |`n"
    $md += "| Repeated searches | $repeatedCount |`n"
}
$md | Out-File "$OutputDir\langfuse-gettypeinfo.md" -Encoding utf8

# 9. System Reminders
Write-Host "Generating system reminders..."
$reminders = Invoke-Tool "Get-SystemReminders"
$md = "# System Reminders: $SessionId`n`n"
if ($reminders.Count -eq 0) {
    $md += "No system reminders fired during this session.`n"
} else {
    $md += "## Reminders`n`n"
    $num = 1
    foreach ($rem in $reminders) {
        $md += "### Reminder $num`n`n"
        $md += "**Time**: $($rem.Time)`n"
        $md += "**Analyser**: $($rem.Analyser)`n"
        $md += "**Message**: $($rem.Message)`n"
        if ($rem.NextAction) {
            $md += "**Next Action**: $($rem.NextAction)`n"
        }
        $md += "`n"
        $num++
    }

    $byAnalyser = $reminders | Group-Object Analyser
    $md += "## Summary`n`n"
    $md += "| Analyser | Count |`n"
    $md += "|----------|-------|`n"
    foreach ($group in $byAnalyser) {
        $md += "| $($group.Name) | $($group.Count) |`n"
    }
}
$md | Out-File "$OutputDir\langfuse-system-reminders.md" -Encoding utf8

# 10. CSharp Refactorings
Write-Host "Generating CSharp refactorings..."
$refactorings = Invoke-Tool "Get-CSharpRefactorings"
$md = "# CSharp Refactorings: $SessionId`n`n"
if ($refactorings.Count -eq 0) {
    $md += "No CSharp refactorings applied during this session.`n"
} else {
    $md += "## Refactorings`n`n"
    $md += "| Trace | File | Rules Applied | Count |`n"
    $md += "|-------|------|---------------|-------|`n"
    foreach ($ref in $refactorings) {
        $md += "| $($ref.Trace) | $($ref.FilePath) | $($ref.Rules) | $($ref.RuleCount) |`n"
    }

    $totalFiles = ($refactorings | Select-Object -ExpandProperty FilePath -Unique).Count
    $totalRules = ($refactorings | Measure-Object -Property RuleCount -Sum).Sum
    # Split comma-separated rules and count frequency
    $allRules = $refactorings | ForEach-Object { if ($_.Rules) { $_.Rules -split ',\s*' } } | Where-Object { $_ }
    $ruleFreq = $allRules | Group-Object | Sort-Object Count -Descending | Select-Object -First 5
    $highRuleFiles = $refactorings | Sort-Object RuleCount -Descending | Select-Object -First 3

    $md += "`n## Summary`n`n"
    $md += "| Metric | Value |`n"
    $md += "|--------|-------|`n"
    $md += "| Total files refactored | $totalFiles |`n"
    $md += "| Total rule applications | $totalRules |`n"
    if ($ruleFreq) {
        $topRules = ($ruleFreq | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ", "
        $md += "| Most frequent rules | $topRules |`n"
    }
    if ($highRuleFiles) {
        $highFiles = ($highRuleFiles | ForEach-Object { "$($_.FilePath) ($($_.RuleCount) rules)" }) -join ", "
        $md += "| High rule-count files | $highFiles |`n"
    }
}
$md | Out-File "$OutputDir\langfuse-refactorings.md" -Encoding utf8

Write-Host "All reports generated successfully in $OutputDir"
