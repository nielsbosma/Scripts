param([Parameter(ValueFromRemainingArguments)][string[]]$Args)

function Sync-Repo {
    param([string]$Path)
    Write-Host "Syncing $Path..." -ForegroundColor Cyan
    Push-Location $Path
    try {
        $status = git status --porcelain
        if ($status) {
            Write-Host "  Local changes detected in $Path" -ForegroundColor Yellow
            $choice = Read-Host "  Continue anyway? (y/n)"
            if ($choice -ne 'y') { Pop-Location; exit 1 }
            return
        }
        git pull
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Git pull failed in $Path" -ForegroundColor Red
            $choice = Read-Host "  Continue anyway? (y/n)"
            if ($choice -ne 'y') { Pop-Location; exit 1 }
        }
    } finally {
        Pop-Location
    }
}

Sync-Repo "D:\Repos\_Ivy\Ivy-Framework"
Sync-Repo "D:\Repos\_Ivy\Ivy-Tendril"

Get-Process -Name "Ivy.Tendril" -ErrorAction SilentlyContinue | Stop-Process -Force

Set-Location "D:\Repos\_Ivy\Ivy-Tendril\src\Ivy.Tendril"
if ($Args.Count -gt 0) {
    dotnet run -- @Args --find-available-port --browse --enable-dev-tools
} else {
    dotnet run -- --find-available-port --browse --enable-dev-tools
}
