param(
    [string]$Prompt
)

# Get prompt from parameter or ask user
if ([string]::IsNullOrWhiteSpace($Prompt)) {
    $Prompt = Read-Host "Enter the prompt for db generate"
    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        Write-Error "Prompt is required"
        exit 1
    }
}

CreateNewIvyTempProject.ps1

ivy-local db generate --use-console --debug-agent-server http://localhost:5122 --skip-debug --yes-to-all --prompt "$Prompt"
$exitCode = $LASTEXITCODE

switch ($exitCode) {
    0 {
        Write-Host "Success!" -ForegroundColor Green
    }
    1 {
        Write-Host "Failed - General failure" -ForegroundColor Red
    }
    2 {
        Write-Host "Failed - DBML is wrong" -ForegroundColor Red
    }
    3 {
        Write-Host "Failed - DatabaseGenerator build error. Starting debug loop..." -ForegroundColor Yellow
        Push-Location .ivy/DatabaseGenerator
        try {
            IvyDebugLoop.ps1
        }
        finally {
            Pop-Location
        }
    }
    4 {
        Write-Host "Failed - DatabaseGenerator run error. Starting debug loop with RecreateDatabase..." -ForegroundColor Yellow
        Push-Location .ivy/DatabaseGenerator
        try {
            IvyDebugLoop.ps1 -BuildCommand "./RecreateDatabase.ps1"
        }
        finally {
            Pop-Location
        }
    }
    5 {
        Write-Host "Failed - Project error. Starting debug loop..." -ForegroundColor Yellow
        IvyDebugLoop.ps1
    }
    default {
        Write-Host "Unknown exit code: $exitCode" -ForegroundColor Red
    }
}