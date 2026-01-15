<#
.SYNOPSIS
    Extracts URLs from a file and checks their HTTP status codes.

.DESCRIPTION
    Parses a file for URLs, then makes HTTP HEAD requests to check if each URL
    returns a 200 (OK) or 404 (Not Found) status, or other status codes.

.PARAMETER Path
    The path to the file containing URLs to check.

.PARAMETER Timeout
    Timeout in seconds for each HTTP request. Default is 10.

.EXAMPLE
    .\CheckUrls.ps1 -Path "README.md"

.EXAMPLE
    .\CheckUrls.ps1 -Path "links.txt" -Timeout 30
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$Path,

    [Parameter()]
    [int]$Timeout = 10
)

$ErrorActionPreference = 'Stop'

# URL regex pattern - matches http and https URLs
$urlPattern = 'https?://[^\s\)\]\>\"\''<]+'

# Read file content
$content = Get-Content -Path $Path -Raw

# Extract all URLs
$urls = [regex]::Matches($content, $urlPattern) |
    ForEach-Object { $_.Value.TrimEnd('.', ',', ')', ']', '>', '"', "'") } |
    Sort-Object -Unique

if ($urls.Count -eq 0) {
    Write-Host "No URLs found in '$Path'" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($urls.Count) unique URL(s) in '$Path'" -ForegroundColor Cyan
Write-Host ""

$results = @()

foreach ($url in $urls) {
    $status = $null
    $statusCode = $null
    $color = 'White'

    try {
        # Use HEAD request first (faster), fall back to GET if HEAD fails
        try {
            $response = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
            $statusCode = $response.StatusCode
        }
        catch {
            # Some servers don't support HEAD, try GET
            $response = Invoke-WebRequest -Uri $url -Method Get -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
            $statusCode = $response.StatusCode
        }

        $status = 'OK'
        $color = 'Green'
    }
    catch {
        $errorResponse = $_.Exception.Response
        if ($errorResponse) {
            $statusCode = [int]$errorResponse.StatusCode
            if ($statusCode -eq 404) {
                $status = 'Not Found'
                $color = 'Red'
            }
            else {
                $status = $errorResponse.StatusCode.ToString()
                $color = 'Yellow'
            }
        }
        else {
            $statusCode = 'N/A'
            $status = $_.Exception.Message -replace '\r?\n', ' '
            $color = 'Red'
        }
    }

    $result = [PSCustomObject]@{
        URL        = $url
        StatusCode = $statusCode
        Status     = $status
    }
    $results += $result

    # Display result
    $codeDisplay = if ($statusCode -eq 'N/A') { '---' } else { $statusCode }
    Write-Host "[$codeDisplay] " -ForegroundColor $color -NoNewline
    Write-Host $url
}

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan

$okCount = ($results | Where-Object { $_.StatusCode -eq 200 }).Count
$notFoundCount = ($results | Where-Object { $_.StatusCode -eq 404 }).Count
$otherCount = $results.Count - $okCount - $notFoundCount

Write-Host "  200 OK:        $okCount" -ForegroundColor Green
Write-Host "  404 Not Found: $notFoundCount" -ForegroundColor Red
Write-Host "  Other:         $otherCount" -ForegroundColor Yellow

# Return results for pipeline usage
$results
