param(
  [Parameter(Mandatory)]
  [string] $Title,

  [string] $Body = "See screenshot below."
)

# --- Function: Find the root of the current git repository ---
function Find-GitRepository {
    $currentPath = Get-Location
    while ($currentPath) {
        if (Test-Path (Join-Path $currentPath ".git")) {
            return $currentPath
        }
        $parent = Split-Path $currentPath -Parent
        if ($parent -eq $currentPath) { break } # reached root
        $currentPath = $parent
    }
    return $null
}

# --- Relaunch in STA if needed for clipboard ---
function Ensure-STA {
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        $psi = @{
            FilePath = (Get-Command pwsh, powershell -ErrorAction SilentlyContinue | Select-Object -First 1).Source
            ArgumentList = @(
                '-NoProfile','-STA','-ExecutionPolicy','Bypass',
                '-File', $PSCommandPath,
                '-Title', $Title,
                '-Body', $Body
            )
            Wait = $true
        }
        Start-Process @psi
        exit
    }
}
Ensure-STA

# --- Ensure GitHub CLI is available and authenticated ---
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) not found. Install from https://cli.github.com/ and run 'gh auth login'."
    exit 1
}
gh auth status 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "You're not authenticated with gh. Run: gh auth login"
    exit 1
}

# --- Find the repo ---
$repoPath = Find-GitRepository
if (-not $repoPath) {
    Write-Error "No .git folder found in current or parent directories."
    exit 2
}
Push-Location $repoPath
try {
    $Repo = gh repo view --json nameWithOwner --jq ".nameWithOwner" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $Repo) {
        Write-Error "Could not determine GitHub repository from current folder."
        exit 3
    }
} finally {
    Pop-Location
}

Write-Host "Repository: $Repo" -ForegroundColor Green

# --- Load clipboard ---
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing       | Out-Null
$image = [System.Windows.Forms.Clipboard]::GetImage()
if (-not $image) {
    Write-Error "No image found in clipboard. Copy a screenshot first (Win+Shift+S) and try again."
    exit 4
}

# --- Save screenshot to temp file ---
$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$pngPath   = Join-Path $env:TEMP ("screenshot_$timestamp.png")
$image.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "Saved clipboard image to: $pngPath" -ForegroundColor Green
Write-Host "File size: $((Get-Item $pngPath).Length / 1KB) KB" -ForegroundColor Gray

# --- Upload to Gist ---
Write-Host "`nAttempting to create gist..." -ForegroundColor Cyan
$desc = "Issue image for $Repo ($([DateTime]::UtcNow.ToString('u')))"

# Test with a simpler command first
Write-Host "Testing gist creation with description: $desc" -ForegroundColor Gray
Write-Host "Command: gh gist create -p -d `"$desc`" `"$pngPath`"" -ForegroundColor Gray

# Capture both stdout and stderr
$gistOutput = @()
$gistErrors = @()
$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = "gh"
$processInfo.Arguments = "gist create -p -d `"$desc`" `"$pngPath`""
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.UseShellExecute = $false
$processInfo.CreateNoWindow = $true

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $processInfo
$process.Start() | Out-Null
$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()
$exitCode = $process.ExitCode

Write-Host "`nGist creation result:" -ForegroundColor Cyan
Write-Host "Exit code: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { 'Green' } else { 'Red' })
if ($stdout) {
    Write-Host "STDOUT:" -ForegroundColor Yellow
    Write-Host $stdout -ForegroundColor Gray
}
if ($stderr) {
    Write-Host "STDERR:" -ForegroundColor Yellow
    Write-Host $stderr -ForegroundColor Gray
}

if ($exitCode -ne 0) {
    Write-Host "`nAlternative: Trying with --public flag explicitly..." -ForegroundColor Cyan
    $altOutput = gh gist create --public -d $desc $pngPath 2>&1
    Write-Host "Alternative output: $altOutput" -ForegroundColor Gray
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`nDiagnostics:" -ForegroundColor Red
        Write-Host "1. Check your gh auth scopes:" -ForegroundColor Yellow
        gh auth status
        Write-Host "`n2. Try creating a simple text gist:" -ForegroundColor Yellow
        "Test gist" | Out-File "$env:TEMP\test.txt"
        $testGist = gh gist create --public -d "Test" "$env:TEMP\test.txt" 2>&1
        Write-Host "Test gist result: $testGist" -ForegroundColor Gray
        
        Write-Error "Failed to create Gist. Check the diagnostics above."
        exit 5
    }
    $gistUrl = $altOutput
} else {
    $gistUrl = $stdout
}

# Parse the URL
$gistUrl = $gistUrl | Where-Object { $_ -match '^https://gist\.github\.com/' } | Select-Object -First 1
if (-not $gistUrl) {
    Write-Host "Could not find URL in output. Full output was:" -ForegroundColor Red
    Write-Host $stdout -ForegroundColor Gray
    Write-Error "Could not parse Gist URL from output"
    exit 5
}

Write-Host "`nGist created successfully: $gistUrl" -ForegroundColor Green
$gistId = ($gistUrl -split '/')[-1]

# --- Get raw URL ---
$fileName = [IO.Path]::GetFileName($pngPath)
Write-Host "Getting raw URL for file: $fileName" -ForegroundColor Cyan
$rawUrl = gh api "gists/$gistId" --jq ".files[\`"$fileName\`"].raw_url"
if ($LASTEXITCODE -ne 0 -or -not $rawUrl) {
    Write-Host "Failed to get raw URL. Trying alternative method..." -ForegroundColor Yellow
    $gistData = gh api "gists/$gistId" | ConvertFrom-Json
    $rawUrl = $gistData.files.$fileName.raw_url
    if (-not $rawUrl) {
        Write-Error "Failed to get raw URL for the uploaded image"
        exit 5
    }
}
Write-Host "Raw URL: $rawUrl" -ForegroundColor Green

# --- Create issue ---
$markdownImage = "![$fileName]($rawUrl)"
$fullBody = "$Body`n`n$markdownImage"
Write-Host "`nCreating issue in $Repo..." -ForegroundColor Cyan
gh issue create --repo $Repo --title $Title --body $fullBody
if ($LASTEXITCODE -eq 0) {
    Write-Host "Issue created in $Repo with embedded screenshot." -ForegroundColor Green
} else {
    Write-Error "Issue creation failed."
}