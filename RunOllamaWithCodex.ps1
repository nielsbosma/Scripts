# Start Ollama and Open Codex together
param(
    [string]$Model = "qwen2.5-coder:14b"
)

# Start Ollama serve in the background if not already running
$ollamaRunning = Get-Process -Name "ollama" -ErrorAction SilentlyContinue
if (-not $ollamaRunning) {
    Write-Host "Starting Ollama..." -ForegroundColor Cyan
    Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep -Seconds 3
} else {
    Write-Host "Ollama is already running." -ForegroundColor Green
}

# Verify Ollama is responding
try {
    $null = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5
    Write-Host "Ollama is ready." -ForegroundColor Green
} catch {
    Write-Host "Ollama failed to start. Check your installation." -ForegroundColor Red
    exit 1
}

# Pull model if not already available
$models = (Invoke-RestMethod -Uri "http://localhost:11434/api/tags").models.name
if ($models -notcontains $Model) {
    Write-Host "Pulling model $Model (this may take a while)..." -ForegroundColor Yellow
    ollama pull $Model
}

# Launch Open Codex pointing at Ollama
$env:OPENAI_BASE_URL = "http://localhost:11434/v1"
$env:OPENAI_API_KEY = "ollama"

Write-Host "Launching Codex with model $Model..." -ForegroundColor Cyan
codex --model $Model
