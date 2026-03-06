param(
    [string]$SessionId = "",
    [switch]$Annotate,
    [string]$Prompt = ""
)

if ([string]::IsNullOrWhiteSpace($SessionId)) {
    $ldjsonPath = Join-Path $PWD ".ivy\session.ldjson"
    if (-not (Test-Path $ldjsonPath)) {
        Write-Host "No SessionId provided and no .ivy\session.ldjson found in current directory."
        exit 1
    }
    $lastLine = (Get-Content -Path $ldjsonPath -Tail 1).Trim()
    $sessionData = $lastLine | ConvertFrom-Json
    $SessionId = $sessionData.sessionId
    if ([string]::IsNullOrWhiteSpace($SessionId)) {
        Write-Host "Could not extract sessionId from $ldjsonPath"
        exit 1
    }
    Write-Host "Auto-detected SessionId: $SessionId"
}

$originalLocation = Get-Location
try {
Set-Location "D:\Repos\_Ivy\Ivy-Agent"

if (-not [string]::IsNullOrWhiteSpace($Prompt)) {
    $content = $Prompt
} else {
    $tempFile = [System.IO.Path]::GetTempFileName() + ".txt"

    if ($Annotate) {
        $logPath = "D:\Temp\ivy-agent\$SessionId\$SessionId-client-output.log"
        if (-not (Test-Path $logPath)) {
            Write-Host "Client output log not found: $logPath"
            exit 1
        }
        $logContent = Get-Content -Path $logPath -Raw
        $initialContent = @"
$logContent
"@
        Set-Content -Path $tempFile -Value $initialContent
    } else {
        Set-Content -Path $tempFile -Value "" -NoNewline
    }

    $process = Start-Process notepad $tempFile -PassThru
    $process.WaitForExit()

    $rawContent = Get-Content -Path $tempFile -Raw
    $content = if ($rawContent) { $rawContent.Trim() -replace '\r?\n', ' ' } else { "" }

    Remove-Item -Path $tempFile -Force

    if ([string]::IsNullOrWhiteSpace($content)) {
        Write-Host "No input provided. Exiting."
        exit 1
    }
}

$prompt = "/debug-agent-session $SessionId $content"

claude --dangerously-skip-permissions $prompt
}
finally {
    Set-Location $originalLocation
}
