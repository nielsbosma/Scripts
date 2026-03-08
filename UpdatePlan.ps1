param(
    [Parameter(Mandatory=$true)]
    [string]$PlanPath,

    [switch]$ReadyToGo
)

# Ensure UTF-8 output encoding so multi-byte characters survive process capture
$prevOutputEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$resolvedPath = Resolve-Path -Path $PlanPath -ErrorAction SilentlyContinue
if (-not $resolvedPath) {
    Write-Host "File not found: $PlanPath"
    exit 1
}
$resolvedPath = $resolvedPath.Path
$originalDir = Split-Path -Parent $resolvedPath
$fileName = Split-Path -Leaf $resolvedPath

# Copy current version to history before updating
$historyDir = Join-Path $originalDir "history"
if (-not (Test-Path $historyDir)) {
    New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
}
$historyPath = Join-Path $historyDir $fileName
Copy-Item -Path $resolvedPath -Destination $historyPath -Force
Write-Host "Previous version saved to: $historyPath"

# Move to updating directory
$updatingDir = "D:\Repos\_Ivy\.plans\updating"
if (-not (Test-Path $updatingDir)) {
    New-Item -ItemType Directory -Path $updatingDir -Force | Out-Null
}
$updatingPath = Join-Path $updatingDir $fileName
Move-Item -Path $resolvedPath -Destination $updatingPath -Force

if (-not $ReadyToGo) {
    # Open in Notepad for user comments
    $notepad = Start-Process notepad.exe -ArgumentList $updatingPath -PassThru
    $notepad.WaitForExit()
}

$fileContent = Get-Content -Path $updatingPath -Raw -Encoding UTF8

if ([string]::IsNullOrWhiteSpace($fileContent)) {
    Write-Host "File was empty. Moving back and aborting."
    Move-Item -Path $updatingPath -Destination $resolvedPath -Force
    exit 1
}

# Check if there are any >> comments
$hasComments = $fileContent -split "`n" | Where-Object { $_ -match '^\s*>>' }
if (-not $hasComments) {
    Write-Host "No >> comments found. Moving back and aborting."
    Move-Item -Path $updatingPath -Destination $resolvedPath -Force
    exit 0
}

$systemPrompt = @"
You are a plan-editing assistant. You receive an implementation plan with user comments (lines prefixed with >>).
Apply the comments and output the complete updated plan.

CRITICAL RULES:
- Output the ENTIRE plan from first line to last line.
- Wrap output in ===PLAN_START=== and ===PLAN_END=== markers.
- DO NOT summarize, abbreviate, or skip sections.
- Remove all >> lines after incorporating their intent.
- Keep the same markdown format, structure, and detail level.
- Output must be at least as long as the original (minus >> lines).
- Do NOT include any reference context or background information in the output — only the plan itself.
- Output ONLY: ===PLAN_START===, then the plan, then ===PLAN_END===. Nothing else.
"@

$contextContent = Get-Content -Path "$PSScriptRoot\PlanContext.md" -Raw

$userPrompt = @"
Apply the >> comments and output the complete updated plan wrapped in ===PLAN_START=== and ===PLAN_END=== markers.

===PLAN TO UPDATE===

$fileContent

===END OF PLAN===

===REFERENCE CONTEXT (DO NOT include this in the output - this is background information only)===

$contextContent

===END OF REFERENCE CONTEXT===
"@

$maxAttempts = 3
$success = $false

for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    if ($attempt -gt 1) {
        Write-Host "Retry attempt $attempt of $maxAttempts..."
    }

    Write-Host "Running Claude to update plan..."
    $combinedPrompt = "$systemPrompt`n`n$userPrompt"
    $rawOutput = ($combinedPrompt | & "$env:USERPROFILE\.local\bin\claude.exe" --dangerously-skip-permissions -p --output-format text) -join "`n"

    if ([string]::IsNullOrWhiteSpace($rawOutput)) {
        Write-Host "WARNING: Claude returned empty output. Attempt $attempt failed."
        continue
    }

    # Extract content between markers if present
    $markerPattern = '(?s)===PLAN_START===\s*\n(.*?)===PLAN_END==='
    $markerMatch = [regex]::Match($rawOutput, $markerPattern)
    if ($markerMatch.Success) {
        $updatedContent = $markerMatch.Groups[1].Value.TrimEnd()
    } else {
        $updatedContent = $rawOutput
    }

    # Normalize line endings and write UTF-8 without BOM
    $updatedContent = $updatedContent -replace "`r`n", "`n" -replace "`r", "`n"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($updatingPath, $updatedContent, $utf8NoBom)

    # Validate output completeness
    $inputLineCount = ($fileContent -split "`n").Count
    $outputLineCount = ($updatedContent -split "`n").Count
    $ratio = $outputLineCount / [Math]::Max($inputLineCount, 1)

    if ($ratio -ge 0.5) {
        $success = $true
        break
    }

    Write-Host "WARNING: Output ($outputLineCount lines) is much shorter than input ($inputLineCount lines). Attempt $attempt failed."
}

if (-not $success) {
    Write-Host "All $maxAttempts attempts failed. Restoring original file from history."
    Copy-Item -Path $historyPath -Destination $resolvedPath -Force
    Remove-Item -Path $updatingPath -Force
    exit 1
}

# Determine version suffix
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
$extension = [System.IO.Path]::GetExtension($fileName)

if ($baseName -match '-v(\d+)$') {
    $currentVersion = [int]$Matches[1]
    $nextVersion = $currentVersion + 1
    $newBaseName = $baseName -replace '-v\d+$', "-v$nextVersion"
} else {
    $newBaseName = "$baseName-v2"
}

$newFileName = "$newBaseName$extension"
$destinationPath = Join-Path $originalDir $newFileName

Move-Item -Path $updatingPath -Destination $destinationPath -Force
Write-Host "Updated plan saved to: $destinationPath"
