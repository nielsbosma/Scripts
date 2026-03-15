# Ensure claude CLI is on the PATH
$claudeDir = Join-Path $env:USERPROFILE ".local\bin"
if (Test-Path $claudeDir) {
    if ($env:PATH -notlike "*$claudeDir*") {
        $env:PATH = "$claudeDir;$env:PATH"
    }
}

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
        [string]$LogFile,
        [string]$ProgramFolder,
        [hashtable]$Values = @{}
    )

    $header = ($Values.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key): $($_.Value)" }) -join "`n"

    $sharedFolder = Join-Path $ScriptRoot ".shared"
    $firmware = Get-Content "$sharedFolder\Firmware.md" -Raw
    $firmware = $firmware.Replace("[HEADER]", $header)
    $firmware = $firmware.Replace("[LOGFILE]", $LogFile)
    $firmware = $firmware.Replace("[PROGRAMFOLDER]", $ProgramFolder)
    $firmware = $firmware.Replace("[SHAREDFOLDER]", $sharedFolder)

    $promptFile = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $promptFile -Value $firmware -NoNewline
    return $promptFile
}

function GetLatestSessionId {
    param([string]$Path = (Join-Path (Get-Location).Path ".ivy\session.ldjson"))

    if (-not (Test-Path $Path)) {
        Write-Host "Error: $Path not found." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }

    $lastLine = (Get-Content $Path -Tail 1).Trim()
    if ($lastLine -eq "") {
        Write-Host "Error: $Path is empty." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }

    return ($lastLine | ConvertFrom-Json).sessionId
}

function InvokeOrOutputPrompt {
    param(
        [string]$ProgramFolder,
        [string]$PromptFile,
        [string]$Prompt,
        [string]$LogFile,
        [switch]$GetPrompt,
        [switch]$GetTaskPrompt,
        [string[]]$ExtraClaudeArgs = @()
    )

    if ($GetPrompt) {
        Get-Content $PromptFile -Raw
        Remove-Item $PromptFile
        return
    }

    if ($GetTaskPrompt) {
        $programMd = Join-Path $ProgramFolder "Program.md"
        $content = if (Test-Path $programMd) { Get-Content $programMd -Raw } else { "(No Program.md found)" }
        Remove-Item $PromptFile
        Write-Output @"
## Task: $([System.IO.Path]::GetFileName($ProgramFolder))

**Working Directory:** $ProgramFolder
**Log File:** $LogFile
**Args:** $Prompt

$content
"@
        return
    }

    Write-Host "Log file: $LogFile"
    Write-Host "Starting Agent..."
    Push-Location $ProgramFolder

    $firmware = Get-Content $PromptFile -Raw
    Remove-Item $PromptFile

    $env:CLAUDECODE = $null
    $env:CLAUDE_CODE_ENTRYPOINT = $null
    claude --dangerously-skip-permissions @ExtraClaudeArgs -- $firmware

    Pop-Location
    return $false
}

function CollectArgs {
    param(
        [string[]]$Arguments,
        [switch]$Optional
    )

    $Arguments = $Arguments | Where-Object { $_ -ne $null -and $_.Trim() -ne "" }
    $joined = ($Arguments -join " ").Trim()

    if ($joined -eq "" -and $Optional) {
        return "(No Args)"
    }

    if ($joined -eq "") {
        $tempFile = [System.IO.Path]::GetTempFileName()
        Write-Host "No arguments provided. Opening Notepad - save the file and close it to continue."
        Start-Process -FilePath "notepad.exe" -ArgumentList $tempFile -Wait
        $joined = ((Get-Content $tempFile) -join " ").Trim()
        Remove-Item $tempFile
    }

    if ($joined -eq "") {
        Write-Host "No arguments provided. Exiting."
        exit
    }

    return $joined
}
