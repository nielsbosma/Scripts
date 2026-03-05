# Create a temp file
$tempFile = [System.IO.Path]::GetTempFileName()
Rename-Item -Path $tempFile -NewName "$tempFile.txt"
$tempFile = "$tempFile.txt"

# Open in Notepad and wait for it to close
Start-Process -FilePath "notepad.exe" -ArgumentList $tempFile -Wait

# Read the file and launch a new PowerShell window for each line
$lines = Get-Content -Path $tempFile | Where-Object { $_.Trim() -ne "" }

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

foreach ($line in $lines) {
    Start-Sleep -Seconds 30
    Start-Process powershell -ArgumentList "-NoExit", "-File", "$scriptDir\IvyAgentRun.ps1", "`"$line`"", "-NoBuild"
}

# Clean up
Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
