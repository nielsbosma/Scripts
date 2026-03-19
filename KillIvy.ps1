# Kill any running ivy-local, ivy, or dotnet processes locking Ivy build output
$processes = Get-Process -Name "ivy-local", "ivy" -ErrorAction SilentlyContinue

# Also find dotnet processes running from Ivy directories
$dotnetProcesses = Get-Process -Name "dotnet" -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.MainModule.FileName } |
    Where-Object {
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine
            $cmdLine -match "Ivy"
        } catch { $false }
    }

$all = @()
if ($processes) { $all += $processes }
if ($dotnetProcesses) { $all += $dotnetProcesses }

if ($all) {
    foreach ($p in $all) {
        Write-Host "Killing $($p.ProcessName) (PID $($p.Id))"
        Stop-Process -Id $p.Id -Force
    }
    Write-Host "Done."
} else {
    Write-Host "No ivy processes found."
}
