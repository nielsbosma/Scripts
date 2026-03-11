#Requires -Version 7.0
param(
    [switch]$Debug
)

# Create a temp file
$tempFile = [System.IO.Path]::GetTempFileName()
Rename-Item -Path $tempFile -NewName "$tempFile.txt"
$tempFile = "$tempFile.txt"

# Open in Notepad and wait for it to close
Start-Process -FilePath "notepad.exe" -ArgumentList $tempFile -Wait

# Read the file and launch a new PowerShell window for each line
$lines = Get-Content -Path $tempFile | Where-Object { $_.Trim() -ne "" }

dotnet build "D:\Repos\_Ivy\Ivy\Ivy.Console\Ivy.Console.csproj"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed. Exiting."
    exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

foreach ($line in $lines) {
    $runArgs = @("-NoExit", "-File", "$scriptDir\IvyAgentRun.ps1", "`"$line`"", "-NoBuild")
    if ($Debug) {
        $runArgs += "-Debug"
    }
    Start-Process pwsh -ArgumentList $runArgs
     Start-Sleep -Seconds 30
}

# Clean up
Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
