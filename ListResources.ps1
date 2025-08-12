<#
.SYNOPSIS
    Lists embedded manifest resources from NuGet packages or DLL files.
    
.DESCRIPTION
    This script extracts and displays embedded manifest resources from either a NuGet package (.nupkg) or a DLL file.
    
.PARAMETER Path
    The path to the NuGet package (.nupkg) or DLL file.
    
.PARAMETER OutputFile
    Optional. Path to output file where the results will be saved.
    
.EXAMPLE
    .\ListResources.ps1 -Path "C:\path\to\package.nupkg"
    Lists embedded resources from the specified NuGet package.
    
.EXAMPLE
    .\ListResources.ps1 -Path "C:\path\to\library.dll"
    Lists embedded resources from the specified DLL file.
    
.EXAMPLE
    .\ListResources.ps1 -Path library.dll
    Lists embedded resources from a DLL in the current directory.
    
.EXAMPLE
    .\ListResources.ps1 -Path "C:\path\to\library.dll" -OutputFile "resources.txt"
    Lists embedded resources from the specified DLL file and saves the output to resources.txt.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputFile
)

function Get-DllResources {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DllPath
    )
    
    # Convert to absolute path if it's relative
    if (-not [System.IO.Path]::IsPathRooted($DllPath)) {
        $DllPath = [System.IO.Path]::GetFullPath((Join-Path $PWD $DllPath))
    }
    
    if (-not (Test-Path -Path $DllPath)) {
        Write-Error "DLL file not found: $DllPath"
        return
    }
    
    try {
        Add-Type -AssemblyName System.Reflection
        $assembly = [System.Reflection.Assembly]::LoadFile($DllPath)
        $resources = $assembly.GetManifestResourceNames()
        
        if ($resources.Count -eq 0) {
            Write-Host "No embedded resources found in the DLL."
        }
        else {
            Write-Host "Found $($resources.Count) embedded resource(s) in $DllPath"
            $resources | ForEach-Object { Write-Output $_ }
        }
        
        return $resources
    }
    catch {
        Write-Error "Error loading DLL: $_"
    }
}

function Get-NugetResources {
    param (
        [Parameter(Mandatory = $true)]
        [string]$NugetPath
    )
    
    # Convert to absolute path if it's relative
    if (-not [System.IO.Path]::IsPathRooted($NugetPath)) {
        $NugetPath = [System.IO.Path]::GetFullPath((Join-Path $PWD $NugetPath))
    }
    
    if (-not (Test-Path -Path $NugetPath)) {
        Write-Error "NuGet package not found: $NugetPath"
        return
    }
    
    if (-not $NugetPath.EndsWith(".nupkg")) {
        Write-Error "The provided file does not appear to be a NuGet package (.nupkg)."
        return
    }
    
    try {
        # Create a temporary directory to extract the package
        $tempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        
        # Extract the NuGet package (essentially a ZIP file)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($NugetPath, $tempDir)
        
        # Find all DLL files in the lib directory
        $dllFiles = Get-ChildItem -Path $tempDir -Filter "*.dll" -Recurse
        
        if ($dllFiles.Count -eq 0) {
            Write-Host "No DLL files found in the NuGet package."
            return
        }
        
        $allResources = @()
        
        foreach ($dll in $dllFiles) {
            Write-Host "Checking DLL: $($dll.FullName)"
            $resources = Get-DllResources -DllPath $dll.FullName
            
            if ($resources -and $resources.Count -gt 0) {
                $allResources += $resources
            }
        }
        
        if ($allResources.Count -eq 0) {
            Write-Host "No embedded resources found in the NuGet package DLLs."
        }
        
        return $allResources
    }
    catch {
        Write-Error "Error processing NuGet package: $_"
    }
    finally {
        # Clean up temporary directory
        if (Test-Path -Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force
        }
    }
}

# Main script execution
try {
    # Convert to absolute path if it's relative
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = [System.IO.Path]::GetFullPath((Join-Path $PWD $Path))
    }
    
    if (-not (Test-Path -Path $Path)) {
        Write-Error "The specified file does not exist: $Path"
        exit 1
    }
    
    $extension = [System.IO.Path]::GetExtension($Path).ToLower()
    $resources = $null
    
    if ($extension -eq ".dll" -or [System.IO.Path]::GetExtension($Path) -eq "") {
        $resources = Get-DllResources -DllPath $Path
    }
    elseif ($extension -eq ".nupkg") {
        $resources = Get-NugetResources -NugetPath $Path
    }
    else {
        Write-Error "Unsupported file type. Please provide a .dll or .nupkg file."
        exit 1
    }
    
    # Always display resources to console, even if also saving to file
    if ($resources -and $resources.Count -gt 0) {
        Write-Host "\nResource names:" -ForegroundColor Cyan
        $resources | ForEach-Object { Write-Output $_ }
    }
    else {
        Write-Host "No resources found." -ForegroundColor Yellow
    }
    
    # Output to file if specified
    if ($OutputFile) {
        if ($resources) {
            $resources | Out-File -FilePath $OutputFile -Force
            Write-Host "Results saved to $OutputFile"
        }
        else {
            "No resources found." | Out-File -FilePath $OutputFile -Force
            Write-Host "No resources found. Empty file created at $OutputFile"
        }
    }
}
catch {
    Write-Error "An error occurred: $_"
    exit 1
}