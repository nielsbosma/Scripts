<#
.SYNOPSIS
    Reranks sections in Hallucinations.md by descending frequency.

.DESCRIPTION
    Parses all ## sections in Hallucinations.md, calculates frequency scores
    based on "Found In:" entries, and reorders sections by descending frequency.

    Scoring rules:
    - Each unique UUID in "Found In:" = 1
    - (multiple sessions) = 3
    - (session not yet recorded) = 1
    - "appeared in ALL sub-tasks" bonus = +2
    - No "Found In:" section = 0
    - "-- now supported" in title = always last (score 999)
    - Ties preserve existing relative order (stable sort)
#>

$HallucinationsPath = "D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared\Docs\05_Other\Hallucinations.md"

if (-not (Test-Path $HallucinationsPath)) {
    Write-Error "Hallucinations.md not found at: $HallucinationsPath"
    exit 1
}

$content = Get-Content $HallucinationsPath -Raw -Encoding UTF8
$lines = Get-Content $HallucinationsPath -Encoding UTF8

# Extract frontmatter and intro (everything before the first ## section)
$firstSectionIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^## ') {
        $firstSectionIndex = $i
        break
    }
}

if ($firstSectionIndex -eq -1) {
    Write-Error "No ## sections found in Hallucinations.md"
    exit 1
}

$preamble = $lines[0..($firstSectionIndex - 1)] -join "`n"

# Split into sections: each starts with "## "
$sections = @()
$currentTitle = $null
$currentLines = @()

for ($i = $firstSectionIndex; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^## ' -and $currentTitle -ne $null) {
        $sections += [PSCustomObject]@{
            Title   = $currentTitle
            Content = $currentLines -join "`n"
            Index   = $sections.Count
        }
        $currentTitle = $lines[$i]
        $currentLines = @($lines[$i])
    }
    elseif ($lines[$i] -match '^## ' -and $currentTitle -eq $null) {
        $currentTitle = $lines[$i]
        $currentLines = @($lines[$i])
    }
    else {
        $currentLines += $lines[$i]
    }
}

# Don't forget the last section
if ($currentTitle -ne $null) {
    $sections += [PSCustomObject]@{
        Title   = $currentTitle
        Content = $currentLines -join "`n"
        Index   = $sections.Count
    }
}

Write-Host "Found $($sections.Count) sections to rerank."

$uuidPattern = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

foreach ($section in $sections) {
    $score = 0
    $isNowSupported = $section.Title -match "[\u2014\-]+\s*now supported"

    if ($isNowSupported) {
        $section | Add-Member -NotePropertyName 'Score' -NotePropertyValue -1
        $section | Add-Member -NotePropertyName 'NowSupported' -NotePropertyValue $true
        continue
    }

    $sectionText = $section.Content

    # Check if section has a "Found In" line
    $hasFoundIn = $sectionText -match '(?i)\*\*Found In[:\*]'
    if (-not $hasFoundIn) {
        # Also check for "### Found In" variant
        $hasFoundIn = $sectionText -match '(?i)###?\s*Found In'
    }

    if ($hasFoundIn) {
        # Extract all unique UUIDs
        $uuids = [regex]::Matches($sectionText, $uuidPattern) | ForEach-Object { $_.Value } | Select-Object -Unique
        $score += $uuids.Count

        # Check for (multiple sessions)
        if ($sectionText -match '\(multiple sessions') {
            $score += 3
        }

        # Check for (session not yet recorded)
        $snyMatches = [regex]::Matches($sectionText, '\(session not yet recorded\)')
        $score += $snyMatches.Count

        # Check for "appeared in ALL sub-tasks" bonus
        if ($sectionText -match 'appeared in ALL sub-tasks') {
            $score += 2
        }
    }

    $section | Add-Member -NotePropertyName 'Score' -NotePropertyValue $score
    $section | Add-Member -NotePropertyName 'NowSupported' -NotePropertyValue $false
}

# Display scores before sorting
Write-Host "`nScores:"
foreach ($section in $sections) {
    $titleShort = ($section.Title -replace '^## ', '').Substring(0, [Math]::Min(60, ($section.Title -replace '^## ', '').Length))
    $label = if ($section.NowSupported) { "NOW SUPPORTED" } else { $section.Score }
    Write-Host "  [$label] $titleShort"
}

# Stable sort: by Score descending, "now supported" last
# PowerShell's Sort-Object is stable, so ties preserve original order
$sorted = $sections | Sort-Object -Property @{Expression = { if ($_.NowSupported) { -9999 } else { $_.Score } }; Descending = $true }, @{Expression = { $_.Index }; Ascending = $true}

# Rebuild the file
$output = $preamble

foreach ($section in $sorted) {
    # Trim trailing whitespace from section content, then add consistent spacing
    $trimmedContent = $section.Content.TrimEnd()
    $output += "`n$trimmedContent`n"
}

# Write back - ensure file ends with single newline
$output = $output.TrimEnd() + "`n"
[System.IO.File]::WriteAllText($HallucinationsPath, $output, [System.Text.UTF8Encoding]::new($false))

Write-Host "`nReranking complete. File updated at: $HallucinationsPath"
