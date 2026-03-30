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
        [switch]$Interactive,
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

    if ($Interactive) {
        & claude --dangerously-skip-permissions --system-prompt $firmware @ExtraClaudeArgs
    } else {
        $agent = GetAgentCommandFromConfig
        & $agent.Executable @($agent.Args) @ExtraClaudeArgs -- $firmware
    }

    Pop-Location
    return $false
}

function MoveApprovedPlans {
    $plansDir = "D:\Repos\_Ivy\.plans"
    $approvedDir = Join-Path $plansDir "approved"
    if (-not (Test-Path $approvedDir)) {
        New-Item -ItemType Directory -Path $approvedDir | Out-Null
    }

    Get-ChildItem -Path $plansDir -Filter "*.md" -File | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        if ($content -match '\[Approved\]') {
            $dest = Join-Path $approvedDir $_.Name
            Move-Item -Path $_.FullName -Destination $dest -Force
            Write-Host "Approved plan moved to: $dest" -ForegroundColor Green
        }
    }
}

function GetAgentCommandFromConfig {
    $configPath = Join-Path (Split-Path $PSScriptRoot) "config.yaml"
    $raw = "claude --print --verbose --output-format stream-json --dangerously-skip-permissions"

    if (Test-Path $configPath) {
        try {
            $yaml = Get-Content $configPath -Raw
            $pattern = "(?m)^agentCommand:\s*(.+)$"
            $match = [regex]::Match($yaml, $pattern)
            if ($match.Success) {
                $raw = $match.Groups[1].Value.Trim()
            }
        }
        catch {
            Write-Host "Warning: Could not parse agentCommand from config.yaml" -ForegroundColor Yellow
        }
    }

    # Split into executable and args
    $parts = $raw -split '\s+', 2
    return @{
        Executable = $parts[0]
        Args = if ($parts.Length -gt 1) { $parts[1] -split '\s+' } else { @() }
    }
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
