param(
    [Parameter(Mandatory = $true)]
    [string]$SessionId
)

Set-Location "D:\Repos\_Ivy\Ivy-Agent"

$tempFile = [System.IO.Path]::GetTempFileName() + ".txt"
Set-Content -Path $tempFile -Value "" -NoNewline

$process = Start-Process notepad $tempFile -PassThru
$process.WaitForExit()

$content = (Get-Content -Path $tempFile -Raw).Trim() -replace '\r?\n', ' '

Remove-Item -Path $tempFile -Force

if ([string]::IsNullOrWhiteSpace($content)) {
    Write-Host "No input provided. Exiting."
    exit 1
}

$prompt = "/debug-agent-session $SessionId $content"

claude --dangerously-skip-permissions $prompt
