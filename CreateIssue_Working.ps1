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
Write-Host "Saved clipboard image to: $pngPath"

# --- Upload to Gist ---
$desc = "Issue image for $Repo ($([DateTime]::UtcNow.ToString('u')))"
# Fixed: Capture the output properly
$gistOutput = gh gist create -p -d $desc $pngPath 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create Gist. Your org may block Gists."
    exit 5
}
# Fixed: Parse the URL from the output more reliably
$gistUrl = $gistOutput | Where-Object { $_ -match '^https://gist\.github\.com/' } | Select-Object -First 1
if (-not $gistUrl) {
    Write-Error "Could not parse Gist URL from output"
    exit 5
}
$gistId = ($gistUrl -split '/')[-1]

# --- Get raw URL ---
$fileName = [IO.Path]::GetFileName($pngPath)
# Fixed: Escape the quotes properly in the JQ expression
$rawUrl = gh api "gists/$gistId" --jq ".files[\`"$fileName\`"].raw_url"
if ($LASTEXITCODE -ne 0 -or -not $rawUrl) {
    Write-Error "Failed to get raw URL for the uploaded image"
    exit 5
}

# --- Create issue ---
$markdownImage = "![$fileName]($rawUrl)"
$fullBody = "$Body`n`n$markdownImage"
gh issue create --repo $Repo --title $Title --body $fullBody
if ($LASTEXITCODE -eq 0) {
    Write-Host "Issue created in $Repo with embedded screenshot."
} else {
    Write-Error "Issue creation failed."
}