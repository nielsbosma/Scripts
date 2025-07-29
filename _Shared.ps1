# Shared.ps1
# Common functions used across multiple scripts

# Function to get the latest tag from a repository
function Get-LatestTag {
    param(
        [string]$RepoPath
    )
    
    try {
        # Change to repo directory and get latest tag
        Push-Location $RepoPath
        
        # Try to get latest release tag first
        $latestRelease = gh release view --json tagName -q .tagName 2>$null
        
        if ($latestRelease) {
            Write-Host "Latest release tag: $latestRelease" -ForegroundColor Green
            return $latestRelease
        }
        
        # If no release, get latest tag
        $latestTag = git describe --tags --abbrev=0 2>$null
        
        if ($latestTag) {
            Write-Host "Latest tag: $latestTag" -ForegroundColor Green
            return $latestTag
        }
        else {
            Write-Host "No tags found in repository" -ForegroundColor Yellow
            return $null
        }
    }
    catch {
        Write-Error "Failed to get latest tag: $_"
        return $null
    }
    finally {
        Pop-Location
    }
}

# Function to increment version tag
function Get-IncrementedVersion {
    param(
        [string]$Tag
    )
    
    # Remove 'v' prefix if present
    $version = $Tag -replace '^v\.?', ''
    
    # Split version into parts
    $parts = $version -split '\.'
    
    if ($parts.Count -eq 3) {
        # Increment patch version
        $major = [int]$parts[0]
        $minor = [int]$parts[1]
        $patch = [int]$parts[2]
        
        $patch++
        
        return "$major.$minor.$patch"
    }
    else {
        Write-Error "Invalid version format: $Tag"
        return $null
    }
}

# Function to create a new release
function New-Release {
    param(
        [string]$Version,
        [string]$RepoPath,
        [string]$Title = "",
        [string]$Notes = "",
        [switch]$Draft = $false,
        [switch]$Prerelease = $false
    )
    
    try {
        Push-Location $RepoPath
        
        # Format the tag with 'v' prefix
        $tag = "v$Version"
        
        Write-Host "`nCreating release:" -ForegroundColor Yellow
        Write-Host "  Tag: $tag" -ForegroundColor Cyan
        Write-Host "  Repository: $RepoPath" -ForegroundColor Cyan
        
        # Build gh release command
        $ghCommand = "gh release create `"$tag`""
        
        if ($Title) {
            $ghCommand += " --title `"$Title`""
        } else {
            $ghCommand += " --title `"Release $tag`""
        }
        
        if ($Notes) {
            $ghCommand += " --notes `"$Notes`""
        } else {
            $ghCommand += " --generate-notes"
        }
        
        if ($Draft) {
            $ghCommand += " --draft"
        }
        
        if ($Prerelease) {
            $ghCommand += " --prerelease"
        }
        
        # Execute the command
        Write-Host "`nExecuting: $ghCommand" -ForegroundColor Gray
        Invoke-Expression $ghCommand
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "`nRelease created successfully!" -ForegroundColor Green
            return $true
        } else {
            Write-Error "Failed to create release"
            return $false
        }
    }
    catch {
        Write-Error "Error creating release: $_"
        return $false
    }
    finally {
        Pop-Location
    }
}

# Function to complete text using OpenAI API
function LlmComplete {
    param(
        [string]$Prompt
    )
    
    $apiKey = $env:OPENAI_API_KEY
    if (-not $apiKey) {
        Write-Error "OPENAI_API_KEY environment variable is not set"
        return $null
    }
    
    $headers = @{
        "Authorization" = "Bearer $apiKey"
        "Content-Type" = "application/json"
    }
    
    $body = @{
        "model" = "gpt-4.1"
        "messages" = @(
            @{
                "role" = "user"
                "content" = $Prompt
            }
        )
        "temperature" = 0.7
        "max_tokens" = 2000
    } | ConvertTo-Json -Depth 10 -Compress
    
    try {
        # Ensure proper UTF-8 encoding
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        
        $response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" `
            -Method Post `
            -Headers $headers `
            -Body $bodyBytes `
            -ContentType "application/json; charset=utf-8" `
            -ErrorAction Stop
        
        return $response.choices[0].message.content
    }
    catch {
        Write-Error "Failed to complete prompt: $_"
        return $null
    }
}

