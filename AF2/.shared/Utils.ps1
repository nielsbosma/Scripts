function GetProgramFolder {
    param([string]$ScriptPath)

    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
    $scriptFolder = Join-Path (Split-Path $ScriptPath) $scriptName
    if (-not (Test-Path $scriptFolder)) {
        New-Item -ItemType Directory -Path $scriptFolder | Out-Null
    }
    return $scriptFolder
}

function GetNextLogFile {
    param([string]$ProgramFolder)

    $logsFolder = Join-Path $ProgramFolder "Logs"
    if (-not (Test-Path $logsFolder)) {
        New-Item -ItemType Directory -Path $logsFolder | Out-Null
    }

    $existing = Get-ChildItem -Path $logsFolder -Filter "*.md" -File |
        Where-Object { $_.BaseName -match '^\d+$' } |
        ForEach-Object { [int]$_.BaseName } |
        Sort-Object -Descending |
        Select-Object -First 1

    $next = if ($existing) { $existing + 1 } else { 1 }
    return Join-Path $logsFolder ("{0:D5}.md" -f $next)
}

function PrepareFirmware {
    param(
        [string]$ScriptRoot,
        [string[]]$Args,
        [string]$LogFile
    )

    $firmware = Get-Content "$ScriptRoot\.shared\Firmware.md" -Raw
    $firmware = $firmware.Replace("[ARGS]", ($Args -join ", "))
    $firmware = $firmware.Replace("[LOGFILE]", $LogFile)
    return $firmware
}

function CollectArgs {
    param(
        [string[]]$Arguments,
        [switch]$Optional
    )

    $Arguments = $Arguments | Where-Object { $_.Trim() -ne "" }

    if ($Arguments.Count -eq 0 -and $Optional) {
        return @("(No Args)")
    }

    if ($Arguments.Count -eq 0) {
        $tempFile = [System.IO.Path]::GetTempFileName()
        Write-Host "No arguments provided. Opening Notepad — save the file and close it to continue."
        Start-Process -FilePath "notepad.exe" -ArgumentList $tempFile -Wait
        $Arguments = Get-Content $tempFile | Where-Object { $_.Trim() -ne "" }
        Remove-Item $tempFile
    }

    if ($Arguments.Count -eq 0) {
        Write-Host "No arguments provided. Exiting."
        exit
    }

    return $Arguments
}
