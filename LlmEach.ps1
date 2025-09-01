param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$FileGlob,
    
    [Parameter(Mandatory=$true, ParameterSetName="Prompt")]
    [string]$Prompt,
    
    [Parameter(Mandatory=$true, ParameterSetName="PromptFile")]
    [string]$PromptFile
)

$ErrorActionPreference = 'Stop'

function Write-ColoredMessage {
    param(
        [string]$Message,
        [ConsoleColor]$Color = 'White'
    )
    Write-Host $Message -ForegroundColor $Color
}

function Show-ProgressBar {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Activity
    )
    
    $percentComplete = ($Current / $Total) * 100
    Write-Progress -Activity $Activity -Status "$Current of $Total completed" -PercentComplete $percentComplete
}

Write-ColoredMessage "Searching for files matching: $FileGlob" -Color Cyan

$matchedFiles = @(Get-ChildItem -Path $FileGlob -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)

if ($matchedFiles.Count -eq 0) {
    Write-ColoredMessage "No files found matching the pattern: $FileGlob" -Color Red
    exit 1
}

Write-ColoredMessage "`nFound $($matchedFiles.Count) file(s):" -Color Green

$displayCount = [Math]::Min(5, $matchedFiles.Count)
for ($i = 0; $i -lt $displayCount; $i++) {
    Write-Host "  $($i + 1). $($matchedFiles[$i])"
}

if ($matchedFiles.Count -gt 5) {
    Write-ColoredMessage "  + $($matchedFiles.Count - 5) more..." -Color DarkGray
}

Write-Host ""
$confirmation = Read-Host "Do you want to proceed? (Y/N)"
if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
    Write-ColoredMessage "Operation cancelled." -Color Yellow
    exit 0
}

if ($PSCmdlet.ParameterSetName -eq "PromptFile") {
    if (-not (Test-Path $PromptFile)) {
        Write-ColoredMessage "Prompt file not found: $PromptFile" -Color Red
        exit 1
    }
    $promptTemplate = Get-Content $PromptFile -Raw
} else {
    $promptTemplate = $Prompt
}

$maxParallel = 5
$runspacePool = [RunspaceFactory]::CreateRunspacePool(1, $maxParallel)
$runspacePool.Open()

$jobs = @()
$results = @{}
$totalJobs = $matchedFiles.Count
$completedJobs = 0

$scriptBlock = {
    param($FilePath, $PromptText)
    
    try {
        # Set working directory for the file
        $workingDir = Split-Path $FilePath -Parent
        
        # Use PowerShell's native command execution
        $result = & claude --dangerously-skip-permissions -p $PromptText 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        
        return @{
            FilePath = $FilePath
            Success = $exitCode -eq 0
            Output = $result
            Error = if ($exitCode -ne 0) { "Command failed with exit code: $exitCode. Output: $result" } else { $null }
        }
    }
    catch {
        return @{
            FilePath = $FilePath
            Success = $false
            Output = ""
            Error = $_.Exception.Message
        }
    }
}

Write-ColoredMessage "`nProcessing $totalJobs file(s) with max $maxParallel parallel jobs..." -Color Cyan

foreach ($file in $matchedFiles) {
    $filePrompt = $promptTemplate -replace '{{File}}', $file
    
    $powershell = [PowerShell]::Create()
    $powershell.RunspacePool = $runspacePool
    [void]$powershell.AddScript($scriptBlock)
    [void]$powershell.AddArgument($file)
    [void]$powershell.AddArgument($filePrompt)
    
    $handle = $powershell.BeginInvoke()
    
    $jobs += [PSCustomObject]@{
        PowerShell = $powershell
        Handle = $handle
        File = $file
    }
    
    while ($jobs.Count -ge $maxParallel) {
        Start-Sleep -Milliseconds 100
        
        $completedJobsInBatch = @($jobs | Where-Object { $_.Handle.IsCompleted })
        
        foreach ($job in $completedJobsInBatch) {
            $result = $job.PowerShell.EndInvoke($job.Handle)
            $results[$job.File] = $result
            $job.PowerShell.Dispose()
            $jobs = @($jobs | Where-Object { $_ -ne $job })
            
            $completedJobs++
            Show-ProgressBar -Current $completedJobs -Total $totalJobs -Activity "Processing files"
            
            if ($result.Success) {
                Write-ColoredMessage "✓ Completed: $($job.File)" -Color Green
            } else {
                Write-ColoredMessage "✗ Failed: $($job.File)" -Color Red
            }
        }
    }
}

while ($jobs.Count -gt 0) {
    Start-Sleep -Milliseconds 100
    
    $completedJobsInBatch = @($jobs | Where-Object { $_.Handle.IsCompleted })
    
    foreach ($job in $completedJobsInBatch) {
        $result = $job.PowerShell.EndInvoke($job.Handle)
        $results[$job.File] = $result
        $job.PowerShell.Dispose()
        $jobs = @($jobs | Where-Object { $_ -ne $job })
        
        $completedJobs++
        Show-ProgressBar -Current $completedJobs -Total $totalJobs -Activity "Processing files"
        
        if ($result.Success) {
            Write-ColoredMessage "✓ Completed: $($job.File)" -Color Green
        } else {
            Write-ColoredMessage "✗ Failed: $($job.File)" -Color Red
        }
    }
}

$runspacePool.Close()
$runspacePool.Dispose()

Write-Progress -Activity "Processing files" -Completed

Write-ColoredMessage "`n========== Summary ==========" -Color Cyan
$successCount = @($results.Values | Where-Object { $_.Success }).Count
$failCount = $totalJobs - $successCount

Write-ColoredMessage "Total: $totalJobs | Success: $successCount | Failed: $failCount" -Color White

if ($failCount -gt 0) {
    Write-ColoredMessage "`nFailed files:" -Color Red
    foreach ($file in $results.Keys) {
        if (-not $results[$file].Success) {
            Write-Host "  - $file"
            if ($results[$file].Error) {
                Write-Host "    Error: $($results[$file].Error)" -ForegroundColor DarkRed
            }
        }
    }
}

Write-ColoredMessage "`nOperation completed." -Color Green
