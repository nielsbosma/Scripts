param(
    [Parameter(Mandatory = $true)]
    [string]$SessionId
)

$tempFile = [System.IO.Path]::GetTempFileName() + ".txt"
Set-Content -Path $tempFile -Value "" -NoNewline

$process = Start-Process notepad $tempFile -PassThru
$process.WaitForExit()

$content = (Get-Content -Path $tempFile -Raw).Trim() -replace '\r?\n', ' '

Remove-Item -Path $tempFile -Force

if ([string]::IsNullOrWhiteSpace($content)) {
    Write-Host "No feedback provided. Exiting."
    exit 1
}

Write-Host "Triggering Session Review workflow..."
Write-Host "  Session ID: $SessionId"
Write-Host "  Feedback:   $content"

gh workflow run review.yaml --repo Ivy-Interactive/Ivy-Agent --ref epic/ivy-coding-agent -f sessionId="$SessionId" -f feedback="$content"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nWorkflow triggered. View at:"
    Write-Host "  https://github.com/Ivy-Interactive/Ivy-Agent/actions/workflows/review.yaml"
} else {
    Write-Host "`nFailed to trigger workflow." -ForegroundColor Red
    exit 1
}
