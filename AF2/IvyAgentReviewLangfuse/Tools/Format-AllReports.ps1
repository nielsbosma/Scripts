<#
.SYNOPSIS
    Generates all formatted markdown reports from langfuse data.
.PARAMETER LangfuseDir
    Path to the langfuse data folder.
.PARAMETER OutputDir
    Path to output directory (e.g., WorkDir/.ivy/)
.PARAMETER SessionId
    Session ID for report headers
.PARAMETER Incomplete
    Whether the session ended prematurely
.PARAMETER Status
    Session status (e.g., Complete, Failed, PrematureStop)
.PARAMETER StopReason
    Reason the session stopped (if incomplete)
#>
param(
    [Parameter(Mandatory)][string]$LangfuseDir,
    [Parameter(Mandatory)][string]$OutputDir,
    [Parameter(Mandatory)][string]$SessionId,
    [switch]$Incomplete,
    [string]$Status = "",
    [string]$StopReason = ""
)

$toolsDir = Split-Path $PSCommandPath -Parent

# Helper to run tool and get objects
function Invoke-Tool($name) {
    @(& "$toolsDir\$name.ps1" -LangfuseDir $LangfuseDir)
}

# Helper to generate incomplete session banner
function Get-IncompleteBanner {
    if ($Incomplete) {
        return "`n> **Warning: Session ended prematurely** — data may be incomplete. Status: $Status, Reason: $StopReason`n"
    }
    return ""
}

# Helper to safely generate a report with error handling
function Write-Report {
    param(
        [string]$Name,
        [string]$FileName,
        [scriptblock]$Generator
    )
    try {
        Write-Host "Generating $Name..."
        $md = & $Generator
        $md | Out-File "$OutputDir\$FileName" -Encoding utf8
    } catch {
        Write-Host "Error generating ${Name}: $_"
        $errorMd = "# ${Name}: $SessionId`n"
        $errorMd += Get-IncompleteBanner
        $errorMd += "`nError generating report: $_`n"
        $errorMd | Out-File "$OutputDir\$FileName" -Encoding utf8
    }
}

$banner = Get-IncompleteBanner

# 1. Timeline
Write-Report -Name "timeline" -FileName "langfuse-timeline.md" -Generator {
    $timeline = Invoke-Tool "Get-Timeline"
    $md = "# Session Timeline: $SessionId`n"
    $md += $banner
    if (-not $timeline -or $timeline.Count -eq 0) {
        if ($Incomplete) {
            $md += "`nNo data available — session ended before this data was generated.`n"
        }
    } else {
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
    }
    $md
}

# 2. Hallucinations
Write-Report -Name "hallucinations" -FileName "langfuse-hallucinations.md" -Generator {
    $hallucinations = Invoke-Tool "Get-Hallucinations"
    $md = "# Hallucination Analysis: $SessionId`n"
    $md += $banner
    if ($hallucinations.Count -eq 0) {
        if ($Incomplete) {
            $md += "`nNo data available — session ended before this data was generated.`n"
        } else {
            $md += "`nNo IvyQuestions found in this session.`n"
        }
    } else {
        $md += "`n## Event Timeline`n`n"
        $md += "| Time | Event | Detail |`n"
        $md += "|------|-------|--------|`n"
        foreach ($evt in $hallucinations) {
            $icon = if ($evt.IsError) { "❌" } else { "" }
            $md += "| $($evt.Time) | $($evt.EventType) | $icon $($evt.Detail) |`n"
        }
    }
    $md
}

# 3. Questions
Write-Report -Name "questions" -FileName "langfuse-questions.md" -Generator {
    $questions = Invoke-Tool "Get-IvyQuestions"
    $md = "# IvyQuestion Log: $SessionId`n"
    $md += $banner
    $requests = $questions | Where-Object { $_.Direction -eq "Request" }
    $responses = $questions | Where-Object { $_.Direction -eq "Response" }
    if ($requests.Count -eq 0) {
        if ($Incomplete) {
            $md += "`nNo data available — session ended before this data was generated.`n"
        } else {
            $md += "`nNo IvyQuestions asked during this session.`n"
        }
    } else {
        $md += "`n## Questions`n`n"
        $qNum = 1
        foreach ($req in $requests) {
            # Find matching response (next response in same trace after this request)
            $resp = $responses | Where-Object { $_.TraceName -eq $req.TraceName -and $_.ObservationFile -gt $req.ObservationFile } | Select-Object -First 1
            $status = if ($resp -and $resp.Success) { "✅ Success" } elseif ($resp) { "❌ Failed" } else { "❓ No response" }
            $md += "### Q$qNum`: $($req.Question)`n`n"
            $md += "**Source**: $($req.Source)`n"
            $md += "**Status**: $status`n"
            if ($resp -and $resp.Success) {
                $md += "**Answer length**: $($resp.AnswerLength) chars`n"
            } elseif ($resp -and $resp.Error) {
                $md += "**Error**: $($resp.Error)`n"
            }
            $md += "`n"
            $qNum++
        }

        $successCount = ($responses | Where-Object { $_.Success -eq $true }).Count
        $failedCount = ($responses | Where-Object { $_.Success -eq $false }).Count
        $totalChars = ($responses | Where-Object { $_.Success -eq $true } | Measure-Object -Property AnswerLength -Sum).Sum

        $md += "## Summary`n`n"
        $md += "| Metric | Count |`n"
        $md += "|--------|-------|`n"
        $md += "| Total IvyQuestions | $($requests.Count) |`n"
        $md += "| Successful | $successCount |`n"
        $md += "| Failed | $failedCount |`n"
        $md += "| Total answer chars | $totalChars |`n"
    }
    $md
}

# 4. Workflows
Write-Report -Name "workflows" -FileName "langfuse-workflows.md" -Generator {
    $workflows = Invoke-Tool "Get-Workflows"
    $md = "# Workflows: $SessionId`n"
    $md += $banner
    if ($workflows.Count -eq 0) {
        $md += "`nNo workflow events found.`n"
    } else {
        $workflowGroups = $workflows | Where-Object { $_.WorkflowName } | Group-Object WorkflowName
        foreach ($wf in $workflowGroups) {
            $events = $wf.Group
            $hasFailed = $events | Where-Object { $_.EventType -eq "Failed" }
            $hasFinished = ($events | Where-Object { $_.EventType -eq "Finished" -and $_.Success }) -or ($events | Where-Object { $_.EventType -eq "State" -and $_.StateName -eq "Finished" })
            $status = if ($hasFailed -and $hasFinished) { "🔄 Recovered" } elseif ($hasFailed) { "❌ Failed" } elseif ($hasFinished) { "✅ Success" } else { "🔄 Running" }

            $md += "`n## $($wf.Name)`n`n"
            $md += "**Status**: $status`n"

            $states = $events | Where-Object { $_.StateName } | Select-Object -ExpandProperty StateName -Unique
            if ($states) {
                $md += "**States**: $($states -join ' -> ')`n"
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
            $hasFailed = $events | Where-Object { $_.EventType -eq "Failed" }
            $hasFinished = ($events | Where-Object { $_.EventType -eq "Finished" -and $_.Success }) -or ($events | Where-Object { $_.EventType -eq "State" -and $_.StateName -eq "Finished" })
            $status = if ($hasFailed -and $hasFinished) { "🔄" } elseif ($hasFailed) { "❌" } elseif ($hasFinished) { "✅" } else { "🔄" }
            $transCount = ($events | Where-Object { $_.EventType -eq "Transition" }).Count
            $md += "| $($wf.Name) | $status | $transCount |`n"
        }
    }
    $md
}

# 5. Reference Connections
Write-Report -Name "reference connections" -FileName "langfuse-reference-connections.md" -Generator {
    $refs = Invoke-Tool "Get-ReferenceConnections"
    $md = "# Reference Connections: $SessionId`n"
    $md += $banner
    if ($refs.Count -eq 0) {
        $md += "`nNo reference connections used.`n"
    } else {
        $md += "`n## Connections Used`n`n"
        $md += "| Connection | Size |`n"
        $md += "|------------|------|`n"
        foreach ($ref in $refs | Select-Object -Property ReferenceName, ContentChars -Unique) {
            $md += "| $($ref.ReferenceName) | $($ref.ContentChars) chars |`n"
        }
    }
    $md
}

# 6. Docs Read
Write-Report -Name "docs read" -FileName "langfuse-docs.md" -Generator {
    $docs = Invoke-Tool "Get-DocsRead"
    $md = "# Docs Read: $SessionId`n"
    $md += $banner
    if ($docs.Count -eq 0) {
        $md += "`nNo IvyDocs read during this session.`n"
    } else {
        $md += "`n## Documents`n`n"
        $md += "| # | Trace | Path | Status | Size |`n"
        $md += "|---|-------|------|--------|------|`n"
        $num = 1
        foreach ($doc in $docs) {
            $status = if ($doc.Success) { "✅" } else { "❌ $($doc.Error)" }
            $size = if ($doc.Success) { "$($doc.ContentLength) chars" } else { "" }
            $md += "| $num | $($doc.TraceName) | $($doc.Path) | $status | $size |`n"
            $num++
        }

        $successful = @($docs | Where-Object Success).Count
        $failed = @($docs | Where-Object { -not $_.Success }).Count
        $totalChars = ($docs | Where-Object Success | Measure-Object -Property ContentLength -Sum).Sum

        $md += "`n## Summary`n`n"
        $md += "| Metric | Count |`n"
        $md += "|--------|-------|`n"
        $md += "| Total doc reads | $($docs.Count) |`n"
        $md += "| Successful | $successful |`n"
        $md += "| Failed | $failed |`n"
        $md += "| Total chars read | $totalChars |`n"
    }
    $md
}

# 7. Build Errors
Write-Report -Name "build errors" -FileName "langfuse-build-errors.md" -Generator {
    $builds = Invoke-Tool "Get-BuildErrors"
    $md = "# Build Errors: $SessionId`n"
    $md += $banner
    if ($builds.Count -eq 0) {
        $md += "`nNo builds found.`n"
    } else {
        foreach ($build in $builds) {
            $status = if ($build.Success) { "✅ OK" } else { "❌ FAILED" }
            $md += "`n## Build #$($build.BuildNumber) ($($build.ObservationFile)) - $status`n`n"

            if (-not $build.Success -and $build.Errors) {
                $errByFile = $build.Errors | Group-Object RelativePath
                foreach ($fileGroup in $errByFile) {
                    $md += "### $($fileGroup.Name)`n"
                    foreach ($err in $fileGroup.Group) {
                        $md += "- ``$($err.ErrorCode):$($err.Line)`` - $($err.Message)`n"
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
    $md
}

# 8. GetTypeInfo
Write-Report -Name "GetTypeInfo usage" -FileName "langfuse-gettypeinfo.md" -Generator {
    $typeInfo = Invoke-Tool "Get-TypeInfoUsage"
    $md = "# GetTypeInfo Usage: $SessionId`n"
    $md += $banner
    if ($typeInfo.Count -eq 0) {
        $md += "`nNo GetTypeInfo calls found.`n"
    } else {
        $md += "`n## Lookups`n`n"
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
    $md
}

# 9. System Reminders
Write-Report -Name "system reminders" -FileName "langfuse-system-reminders.md" -Generator {
    $reminders = Invoke-Tool "Get-SystemReminders"
    $md = "# System Reminders: $SessionId`n"
    $md += $banner
    if ($reminders.Count -eq 0) {
        $md += "`nNo system reminders fired during this session.`n"
    } else {
        $md += "`n## Reminders`n`n"
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
    $md
}

# 10. CSharp Refactorings
Write-Report -Name "CSharp refactorings" -FileName "langfuse-refactorings.md" -Generator {
    $refactorings = Invoke-Tool "Get-CSharpRefactorings"
    $md = "# CSharp Refactorings: $SessionId`n"
    $md += $banner
    if ($refactorings.Count -eq 0) {
        $md += "`nNo CSharp refactorings applied during this session.`n"
    } else {
        $md += "`n## Refactorings`n`n"
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
    $md
}

Write-Host "All reports generated successfully in $OutputDir"
