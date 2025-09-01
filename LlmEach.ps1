param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$FileGlob,
    
    [Parameter(Mandatory=$true, ParameterSetName="Prompt")]
    [string]$Prompt,
    
    [Parameter(Mandatory=$true, ParameterSetName="PromptFile")]
    [string]$PromptFile,
    
    [Parameter()]
    [switch]$Select
)

$ErrorActionPreference = 'Stop'

# Try to import Spectre.Console module
$spectreAvailable = $false
try {
    Import-Module PwshSpectreConsole -ErrorAction Stop
    $spectreAvailable = $true
} catch {
    # Spectre.Console not available, will fall back to standard output
}

function Write-ColoredMessage {
    param(
        [string]$Message,
        [ConsoleColor]$Color = 'White'
    )
    if ($spectreAvailable) {
        $spectreColor = switch ($Color) {
            'Red' { 'red' }
            'Green' { 'green' }
            'Yellow' { 'yellow' }
            'Cyan' { 'cyan' }
            'DarkGray' { 'grey' }
            'DarkRed' { 'darkred' }
            default { 'white' }
        }
        Write-SpectreHost "[$spectreColor]$Message[/]"
    } else {
        Write-Host $Message -ForegroundColor $Color
    }
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

function Select-Files {
    param(
        [string[]]$Files
    )
    
    if ($spectreAvailable) {
        # Create selection choices with file names
        $choices = @()
        for ($i = 0; $i -lt $Files.Count; $i++) {
            $fileName = Split-Path $Files[$i] -Leaf
            $dir = Split-Path $Files[$i] -Parent
            $choices += @{
                Display = "$fileName [grey]($dir)[/]"
                Value = $Files[$i]
            }
        }
        
        # Use Spectre.Console multi-selection
        $selected = Read-SpectreMultiSelection -Title "[cyan]Select files to process:[/]" -Choices $choices -PageSize 15 -ChoiceLabelProperty Display
        
        if ($selected.Count -eq 0) {
            return @()
        }
        
        return $selected | ForEach-Object { $_.Value }
    } else {
        # Fallback to original selection method
        Write-Host ""
        for ($i = 0; $i -lt $Files.Count; $i++) {
            Write-Host "  [$($i + 1)] $($Files[$i])"
        }
        
        Write-Host ""
        Write-ColoredMessage "Enter file numbers to process (comma-separated, e.g., 1,3,5) or 'all' for all files:" -Color Cyan
        $selection = Read-Host "Selection"
        
        if ($selection -eq 'all' -or $selection -eq 'ALL') {
            return $Files
        } else {
            $selectedIndices = @()
            foreach ($num in ($selection -split ',')) {
                $num = $num.Trim()
                if ($num -match '^\d+$') {
                    $index = [int]$num - 1
                    if ($index -ge 0 -and $index -lt $Files.Count) {
                        $selectedIndices += $index
                    } else {
                        Write-ColoredMessage "Warning: Ignoring invalid selection: $num (out of range)" -Color Yellow
                    }
                } else {
                    Write-ColoredMessage "Warning: Ignoring invalid selection: $num (not a number)" -Color Yellow
                }
            }
            
            if ($selectedIndices.Count -eq 0) {
                return @()
            }
            
            $selectedFiles = @()
            foreach ($idx in $selectedIndices) {
                $selectedFiles += $Files[$idx]
            }
            return $selectedFiles
        }
    }
}

# Search for files
if ($spectreAvailable) {
    Write-SpectreRule "[cyan]Searching for files[/]"
    Write-SpectreHost "Pattern: [yellow]$FileGlob[/]"
} else {
    Write-ColoredMessage "Searching for files matching: $FileGlob" -Color Cyan
}

$matchedFiles = @(Get-ChildItem -Path $FileGlob -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)

if ($matchedFiles.Count -eq 0) {
    Write-ColoredMessage "No files found matching the pattern: $FileGlob" -Color Red
    exit 1
}

Write-ColoredMessage "`nFound $($matchedFiles.Count) file(s)" -Color Green

# File selection
if ($Select) {
    $matchedFiles = Select-Files -Files $matchedFiles
    
    if ($matchedFiles.Count -eq 0) {
        Write-ColoredMessage "No files selected. Operation cancelled." -Color Red
        exit 0
    }
    
    if ($spectreAvailable) {
        Write-SpectreRule "[green]Selected $($matchedFiles.Count) file(s) for processing[/]"
        $matchedFiles | ForEach-Object {
            $fileName = Split-Path $_ -Leaf
            $dir = Split-Path $_ -Parent
            Write-SpectreHost "  [white]•[/] $fileName [grey]($dir)[/]"
        }
    } else {
        Write-ColoredMessage "`nSelected $($matchedFiles.Count) file(s) for processing:" -Color Green
        foreach ($file in $matchedFiles) {
            Write-Host "  - $file"
        }
    }
} else {
    # Original behavior - show first 5 files
    if ($spectreAvailable) {
        Write-SpectreRule "[green]Files to process[/]"
        $displayCount = [Math]::Min(5, $matchedFiles.Count)
        for ($i = 0; $i -lt $displayCount; $i++) {
            Write-SpectreHost "  $($i + 1). $($matchedFiles[$i])"
        }
        if ($matchedFiles.Count -gt 5) {
            Write-SpectreHost "  [grey]+ $($matchedFiles.Count - 5) more...[/]"
        }
    } else {
        $displayCount = [Math]::Min(5, $matchedFiles.Count)
        for ($i = 0; $i -lt $displayCount; $i++) {
            Write-Host "  $($i + 1). $($matchedFiles[$i])"
        }
        if ($matchedFiles.Count -gt 5) {
            Write-ColoredMessage "  + $($matchedFiles.Count - 5) more..." -Color DarkGray
        }
    }
}

# Confirmation
Write-Host ""
if ($spectreAvailable) {
    $confirm = Read-SpectreConfirm -Prompt "[yellow]Do you want to proceed?[/]" -DefaultAnswer "n"
    if (-not $confirm) {
        Write-ColoredMessage "Operation cancelled." -Color Yellow
        exit 0
    }
} else {
    $confirmation = Read-Host "Do you want to proceed? (Y/N)"
    if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
        Write-ColoredMessage "Operation cancelled." -Color Yellow
        exit 0
    }
}

# Load prompt template
if ($PSCmdlet.ParameterSetName -eq "PromptFile") {
    if (-not (Test-Path $PromptFile)) {
        Write-ColoredMessage "Prompt file not found: $PromptFile" -Color Red
        exit 1
    }
    $promptTemplate = Get-Content $PromptFile -Raw
} else {
    $promptTemplate = $Prompt
}

# Setup parallel processing
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

# Processing with progress
if ($spectreAvailable) {
    Write-SpectreRule "[cyan]Processing Files[/]"
    Write-SpectreHost "Processing [yellow]$totalJobs[/] file(s) with max [yellow]$maxParallel[/] parallel jobs..."
    Write-Host ""
} else {
    Write-ColoredMessage "`nProcessing $totalJobs file(s) with max $maxParallel parallel jobs..." -Color Cyan
}

$jobIndex = 0
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
        JobIndex = $jobIndex
    }
    
    $jobIndex++
    
    while ($jobs.Count -ge $maxParallel) {
        Start-Sleep -Milliseconds 100
        
        $completedJobsInBatch = @($jobs | Where-Object { $_.Handle.IsCompleted })
        
        foreach ($job in $completedJobsInBatch) {
            $result = $job.PowerShell.EndInvoke($job.Handle)
            $results[$job.File] = $result
            $job.PowerShell.Dispose()
            
            $completedJobs++
            
            Show-ProgressBar -Current $completedJobs -Total $totalJobs -Activity "Processing files"
            
            if ($result.Success) {
                Write-ColoredMessage "[[OK]] Completed: $($job.File)" -Color Green
            } else {
                Write-ColoredMessage "[[FAILED]] Failed: $($job.File)" -Color Red
            }
            
            $jobs = @($jobs | Where-Object { $_ -ne $job })
        }
    }
}

# Wait for remaining jobs
while ($jobs.Count -gt 0) {
    Start-Sleep -Milliseconds 100
    
    $completedJobsInBatch = @($jobs | Where-Object { $_.Handle.IsCompleted })
    
    foreach ($job in $completedJobsInBatch) {
        $result = $job.PowerShell.EndInvoke($job.Handle)
        $results[$job.File] = $result
        $job.PowerShell.Dispose()
        
        $completedJobs++
        
        Show-ProgressBar -Current $completedJobs -Total $totalJobs -Activity "Processing files"
        
        if ($result.Success) {
            Write-ColoredMessage "[[OK]] Completed: $($job.File)" -Color Green
        } else {
            Write-ColoredMessage "[[FAILED]] Failed: $($job.File)" -Color Red
        }
        
        $jobs = @($jobs | Where-Object { $_ -ne $job })
    }
}

$runspacePool.Close()
$runspacePool.Dispose()

Write-Progress -Activity "Processing files" -Completed

# Summary
$successCount = @($results.Values | Where-Object { $_.Success }).Count
$failCount = $totalJobs - $successCount

if ($spectreAvailable) {
    Write-SpectreRule "[cyan]Summary[/]"
    
    # Create table data
    $tableData = @(
        @{ Metric = "Total Files"; Count = $totalJobs }
        @{ Metric = "Successful"; Count = $successCount }
        @{ Metric = "Failed"; Count = $failCount }
    )
    
    # Format and display the table
    $tableData | Format-SpectreTable
    
    if ($failCount -gt 0) {
        Write-SpectreRule "[red]Failed Files[/]"
        foreach ($file in $results.Keys) {
            if (-not $results[$file].Success) {
                $fileName = Split-Path $file -Leaf
                $dir = Split-Path $file -Parent
                Write-SpectreHost "  [red]x[/] $fileName [grey]($dir)[/]"
                if ($results[$file].Error) {
                    $errorMsg = '    [darkred]Error: ' + $results[$file].Error + '[/]'
                    Write-SpectreHost $errorMsg
                }
            }
        }
    }
    
    Write-Host ""
    
    # Handle failed items - ask to rerun
    if ($failCount -gt 0) {
        Write-Host ""
        $rerunConfirm = Read-SpectreConfirm -Prompt "[yellow]Would you like to rerun the failed files?[/]" -DefaultAnswer "n"
        if ($rerunConfirm) {
            # Collect failed files
            $failedFiles = @()
            foreach ($file in $results.Keys) {
                if (-not $results[$file].Success) {
                    $failedFiles += $file
                }
            }
            
            # Rerun the script with failed files
            Write-SpectreRule "[yellow]Rerunning Failed Files[/]"
            Write-SpectreHost "Reprocessing [red]$($failedFiles.Count)[/] failed file(s)..."
            Write-Host ""
            
            # Re-execute for failed files
            $rerunJobs = @()
            $rerunResults = @{}
            $rerunCompletedJobs = 0
            $rerunTotalJobs = $failedFiles.Count
            
            # Reopen runspace pool for rerun
            $runspacePool = [RunspaceFactory]::CreateRunspacePool(1, $maxParallel)
            $runspacePool.Open()
            
            $jobIndex = 0
            foreach ($file in $failedFiles) {
                $filePrompt = $promptTemplate -replace '{{File}}', $file
                
                $powershell = [PowerShell]::Create()
                $powershell.RunspacePool = $runspacePool
                [void]$powershell.AddScript($scriptBlock)
                [void]$powershell.AddArgument($file)
                [void]$powershell.AddArgument($filePrompt)
                
                $handle = $powershell.BeginInvoke()
                
                $rerunJobs += [PSCustomObject]@{
                    PowerShell = $powershell
                    Handle = $handle
                    File = $file
                    JobIndex = $jobIndex
                }
                
                $jobIndex++
                
                while ($rerunJobs.Count -ge $maxParallel) {
                    Start-Sleep -Milliseconds 100
                    
                    $completedJobsInBatch = @($rerunJobs | Where-Object { $_.Handle.IsCompleted })
                    
                    foreach ($job in $completedJobsInBatch) {
                        $result = $job.PowerShell.EndInvoke($job.Handle)
                        $rerunResults[$job.File] = $result
                        $job.PowerShell.Dispose()
                        
                        $rerunCompletedJobs++
                        
                        Show-ProgressBar -Current $rerunCompletedJobs -Total $rerunTotalJobs -Activity "Reprocessing failed files"
                        
                        if ($result.Success) {
                            Write-ColoredMessage "[[RETRY OK]] Completed: $($job.File)" -Color Green
                        } else {
                            Write-ColoredMessage "[[RETRY FAILED]] Still failing: $($job.File)" -Color Red
                        }
                        
                        $rerunJobs = @($rerunJobs | Where-Object { $_ -ne $job })
                    }
                }
            }
            
            # Wait for remaining rerun jobs
            while ($rerunJobs.Count -gt 0) {
                Start-Sleep -Milliseconds 100
                
                $completedJobsInBatch = @($rerunJobs | Where-Object { $_.Handle.IsCompleted })
                
                foreach ($job in $completedJobsInBatch) {
                    $result = $job.PowerShell.EndInvoke($job.Handle)
                    $rerunResults[$job.File] = $result
                    $job.PowerShell.Dispose()
                    
                    $rerunCompletedJobs++
                    
                    Show-ProgressBar -Current $rerunCompletedJobs -Total $rerunTotalJobs -Activity "Reprocessing failed files"
                    
                    if ($result.Success) {
                        Write-ColoredMessage "[[RETRY OK]] Completed: $($job.File)" -Color Green
                    } else {
                        Write-ColoredMessage "[[RETRY FAILED]] Still failing: $($job.File)" -Color Red
                    }
                    
                    $rerunJobs = @($rerunJobs | Where-Object { $_ -ne $job })
                }
            }
            
            $runspacePool.Close()
            $runspacePool.Dispose()
            
            Write-Progress -Activity "Reprocessing failed files" -Completed
            
            # Final summary after rerun
            $rerunSuccessCount = @($rerunResults.Values | Where-Object { $_.Success }).Count
            $stillFailedCount = $rerunTotalJobs - $rerunSuccessCount
            
            Write-SpectreRule "[cyan]Rerun Summary[/]"
            
            $rerunTableData = @(
                @{ Metric = "Retried Files"; Count = $rerunTotalJobs }
                @{ Metric = "Now Successful"; Count = $rerunSuccessCount }
                @{ Metric = "Still Failed"; Count = $stillFailedCount }
            )
            
            $rerunTableData | Format-SpectreTable
            
            if ($stillFailedCount -gt 0) {
                Write-SpectreRule "[red]Still Failing Files[/]"
                foreach ($file in $rerunResults.Keys) {
                    if (-not $rerunResults[$file].Success) {
                        $fileName = Split-Path $file -Leaf
                        $dir = Split-Path $file -Parent
                        Write-SpectreHost "  [red]x[/] $fileName [grey]($dir)[/]"
                        if ($rerunResults[$file].Error) {
                            $errorMsg = '    [darkred]Error: ' + $rerunResults[$file].Error + '[/]'
                            Write-SpectreHost $errorMsg
                        }
                    }
                }
            }
        }
    }
    
    Write-SpectreHost '[green]Operation completed[/]'
} else {
    Write-Host ""
    Write-ColoredMessage '========== Summary ==========' -Color Cyan
    $summaryMsg = 'Total: {0} | Success: {1} | Failed: {2}' -f $totalJobs, $successCount, $failCount
    Write-ColoredMessage $summaryMsg -Color White
    
    if ($failCount -gt 0) {
        Write-Host ""
        Write-ColoredMessage 'Failed files:' -Color Red
        foreach ($file in $results.Keys) {
            if (-not $results[$file].Success) {
                Write-Host ('  - ' + $file)
                if ($results[$file].Error) {
                    $errorMsg = '    Error: ' + $results[$file].Error
                    Write-Host $errorMsg -ForegroundColor DarkRed
                }
            }
        }
        
        # Handle failed items - ask to rerun (non-Spectre version)
        Write-Host ""
        Write-ColoredMessage "Would you like to rerun the failed files? (Y/N)" -Color Yellow
        $rerunConfirmation = Read-Host "Rerun"
        
        if ($rerunConfirmation -eq 'Y' -or $rerunConfirmation -eq 'y') {
            # Collect failed files
            $failedFiles = @()
            foreach ($file in $results.Keys) {
                if (-not $results[$file].Success) {
                    $failedFiles += $file
                }
            }
            
            # Rerun the script with failed files
            Write-Host ""
            Write-ColoredMessage "========== Rerunning Failed Files ==========" -Color Yellow
            Write-ColoredMessage "Reprocessing $($failedFiles.Count) failed file(s)..." -Color Yellow
            Write-Host ""
            
            # Re-execute for failed files
            $rerunJobs = @()
            $rerunResults = @{}
            $rerunCompletedJobs = 0
            $rerunTotalJobs = $failedFiles.Count
            
            # Reopen runspace pool for rerun
            $runspacePool = [RunspaceFactory]::CreateRunspacePool(1, $maxParallel)
            $runspacePool.Open()
            
            $jobIndex = 0
            foreach ($file in $failedFiles) {
                $filePrompt = $promptTemplate -replace '{{File}}', $file
                
                $powershell = [PowerShell]::Create()
                $powershell.RunspacePool = $runspacePool
                [void]$powershell.AddScript($scriptBlock)
                [void]$powershell.AddArgument($file)
                [void]$powershell.AddArgument($filePrompt)
                
                $handle = $powershell.BeginInvoke()
                
                $rerunJobs += [PSCustomObject]@{
                    PowerShell = $powershell
                    Handle = $handle
                    File = $file
                    JobIndex = $jobIndex
                }
                
                $jobIndex++
                
                while ($rerunJobs.Count -ge $maxParallel) {
                    Start-Sleep -Milliseconds 100
                    
                    $completedJobsInBatch = @($rerunJobs | Where-Object { $_.Handle.IsCompleted })
                    
                    foreach ($job in $completedJobsInBatch) {
                        $result = $job.PowerShell.EndInvoke($job.Handle)
                        $rerunResults[$job.File] = $result
                        $job.PowerShell.Dispose()
                        
                        $rerunCompletedJobs++
                        
                        Show-ProgressBar -Current $rerunCompletedJobs -Total $rerunTotalJobs -Activity "Reprocessing failed files"
                        
                        if ($result.Success) {
                            Write-ColoredMessage "[[RETRY OK]] Completed: $($job.File)" -Color Green
                        } else {
                            Write-ColoredMessage "[[RETRY FAILED]] Still failing: $($job.File)" -Color Red
                        }
                        
                        $rerunJobs = @($rerunJobs | Where-Object { $_ -ne $job })
                    }
                }
            }
            
            # Wait for remaining rerun jobs
            while ($rerunJobs.Count -gt 0) {
                Start-Sleep -Milliseconds 100
                
                $completedJobsInBatch = @($rerunJobs | Where-Object { $_.Handle.IsCompleted })
                
                foreach ($job in $completedJobsInBatch) {
                    $result = $job.PowerShell.EndInvoke($job.Handle)
                    $rerunResults[$job.File] = $result
                    $job.PowerShell.Dispose()
                    
                    $rerunCompletedJobs++
                    
                    Show-ProgressBar -Current $rerunCompletedJobs -Total $rerunTotalJobs -Activity "Reprocessing failed files"
                    
                    if ($result.Success) {
                        Write-ColoredMessage "[[RETRY OK]] Completed: $($job.File)" -Color Green
                    } else {
                        Write-ColoredMessage "[[RETRY FAILED]] Still failing: $($job.File)" -Color Red
                    }
                    
                    $rerunJobs = @($rerunJobs | Where-Object { $_ -ne $job })
                }
            }
            
            $runspacePool.Close()
            $runspacePool.Dispose()
            
            Write-Progress -Activity "Reprocessing failed files" -Completed
            
            # Final summary after rerun
            $rerunSuccessCount = @($rerunResults.Values | Where-Object { $_.Success }).Count
            $stillFailedCount = $rerunTotalJobs - $rerunSuccessCount
            
            Write-Host ""
            Write-ColoredMessage "========== Rerun Summary ==========" -Color Cyan
            $rerunSummaryMsg = 'Retried: {0} | Now Successful: {1} | Still Failed: {2}' -f $rerunTotalJobs, $rerunSuccessCount, $stillFailedCount
            Write-ColoredMessage $rerunSummaryMsg -Color White
            
            if ($stillFailedCount -gt 0) {
                Write-Host ""
                Write-ColoredMessage 'Still failing files:' -Color Red
                foreach ($file in $rerunResults.Keys) {
                    if (-not $rerunResults[$file].Success) {
                        Write-Host ('  - ' + $file)
                        if ($rerunResults[$file].Error) {
                            $errorMsg = '    Error: ' + $rerunResults[$file].Error
                            Write-Host $errorMsg -ForegroundColor DarkRed
                        }
                    }
                }
            }
        }
    }
    
    Write-Host 'Operation completed.' -ForegroundColor Green
}
