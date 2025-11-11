param(
    [string]$Prompt,
    [string]$ModelId
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

$command = "ivy-local db generate --use-console --debug-agent-server http://localhost:5122 --skip-debug --model-disable-cache --yes-to-all --prompt `"$Prompt`""
if (-not [string]::IsNullOrWhiteSpace($ModelId)) {
    $command += " --model-id `"$ModelId`""
}

Invoke-Expression $command
$exitCode = $LASTEXITCODE

switch ($exitCode) {
    0 {
        Write-Host "Success!" -ForegroundColor Green
    }
    1 {
        Write-Host "Failed - General failure" -ForegroundColor Red
    }
    20 {
        Write-Host "Failed - TODO:DBML is wrong" -ForegroundColor Red
    }
    30 {
        Write-Host "Failed - DatabaseGenerator build error. Starting debug loop..." -ForegroundColor Yellow
        Push-Location .ivy/DatabaseGenerator
        try {
            IvyDebugLoop.ps1
        }
        finally {
            Pop-Location
        }
    }
    40 {
        Write-Host "Failed - Add EF Migration fails. Starting debug loop with AddMigration..." -ForegroundColor Yellow
        Push-Location .ivy/DatabaseGenerator
        try {
            IvyDebugLoop.ps1 -BuildCommand "./AddMigration.ps1"
        }
        finally {
            Pop-Location
        }
    }
    50 {
        Write-Host "Failed - DatabaseGenerator run error. Starting debug loop with RecreateDatabase..." -ForegroundColor Yellow
        Push-Location .ivy/DatabaseGenerator
        try {
            IvyDebugLoop.ps1 -BuildCommand "./RecreateDatabase.ps1"
        }
        finally {
            Pop-Location
        }
    }
    55 {
        Write-Host "Failed - All applications didn't complete" -ForegroundColor Red
    }
    60 {
        Write-Host "Failed - Project error. Starting debug loop..." -ForegroundColor Yellow
        IvyDebugLoop.ps1
    }
    default {
        Write-Host "Unknown exit code: $exitCode" -ForegroundColor Red
    }
}