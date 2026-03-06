param(
    [Parameter(Mandatory=$true)]
    [string]$PlanPath,

    [switch]$ReadyToGo
)

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

$prompt = @"
Update the following implementation plan based on the user's comments (lines prefixed with >>).
Remove the >> comment lines after incorporating them into the plan.
Keep the same plan format and level of detail.
The plan must include all paths and information for an LLM coding agent to execute end-to-end without human intervention.

---

$fileContent

---
"@

Write-Host "Running Claude to update plan..."
$updatedContent = claude --dangerously-skip-permissions -p $prompt
Set-Content -Path $updatingPath -Value $updatedContent -Encoding UTF8

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
