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