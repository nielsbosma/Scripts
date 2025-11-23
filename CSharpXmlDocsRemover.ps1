<#
.SYNOPSIS
    Removes C# XML documentation comments from C# source files.

.DESCRIPTION
    Uses Roslyn's syntax tree to precisely remove SingleLineDocumentationCommentTrivia (///)
    and MultiLineDocumentationCommentTrivia (/** */) without affecting other code.

.PARAMETER Path
    Path to the .cs file(s) to process. Supports wildcards (*.cs) and directories.
    Can be a single file, pattern, directory, or multiple files via pipeline.

.PARAMETER Recursive
    When specified with a directory path, recursively processes all .cs files in subdirectories.

.PARAMETER DryRun
    Shows what would be removed without actually modifying the file.

.PARAMETER Verbose
    Shows detailed processing information.

.EXAMPLE
    .\CSharpXmlDocsRemover.ps1 -Path "MyClass.cs"

.EXAMPLE
    .\CSharpXmlDocsRemover.ps1 -Path "*.cs"

.EXAMPLE
    .\CSharpXmlDocsRemover.ps1 -Path "src" -Recursive

.EXAMPLE
    .\CSharpXmlDocsRemover.ps1 -Path "src/*.cs" -Recursive

.EXAMPLE
    Get-ChildItem -Path "src" -Recurse -Filter "*.cs" | .\CSharpXmlDocsRemover.ps1

.EXAMPLE
    .\CSharpXmlDocsRemover.ps1 -Path "MyClass.cs" -DryRun

.EXAMPLE
    .\CSharpXmlDocsRemover.ps1 -Path "src" -Recursive -DryRun -Verbose
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('FullName')]
    [string[]]$Path,

    [switch]$Recursive,

    [switch]$DryRun
)

begin {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $toolPath = Join-Path $scriptDir "CSharpXmlDocsRemover"
    $exePath = Join-Path $toolPath "bin\Debug\net8.0\CSharpXmlDocsRemover.dll"

    # Check if the tool is built
    if (-not (Test-Path $exePath)) {
        Write-Host "Building C# XML Docs Remover tool..." -ForegroundColor Yellow

        $csprojPath = Join-Path $toolPath "CSharpXmlDocsRemover.csproj"

        if (-not (Test-Path $csprojPath)) {
            Write-Error "Tool not found. Please ensure CSharpXmlDocsRemover project exists at: $toolPath"
            exit 1
        }

        try {
            $buildOutput = dotnet build $csprojPath 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to build tool:`n$buildOutput"
                exit 1
            }
            Write-Host "✓ Tool built successfully" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to build tool: $_"
            exit 1
        }
    }

    $allFiles = @()
}

process {
    if ($Path) {
        foreach ($p in $Path) {
            # Handle wildcards or check if path exists
            if ($p -match '[*?]') {
                # Path contains wildcards - resolve them
                $items = Get-ChildItem -Path $p -ErrorAction SilentlyContinue

                if ($Recursive) {
                    # Get directory from pattern and search recursively
                    $parentDir = Split-Path $p -Parent
                    $pattern = Split-Path $p -Leaf

                    if ([string]::IsNullOrEmpty($parentDir)) {
                        $parentDir = "."
                    }

                    if (Test-Path $parentDir -PathType Container) {
                        $items = Get-ChildItem -Path $parentDir -Filter $pattern -Recurse -File -ErrorAction SilentlyContinue
                    }
                }

                foreach ($item in $items) {
                    if ($item.Extension -eq ".cs") {
                        $allFiles += $item.FullName
                    }
                }
            }
            elseif (Test-Path $p -PathType Container) {
                # Path is a directory
                if ($Recursive) {
                    $items = Get-ChildItem -Path $p -Filter "*.cs" -Recurse -File
                }
                else {
                    $items = Get-ChildItem -Path $p -Filter "*.cs" -File
                }

                foreach ($item in $items) {
                    $allFiles += $item.FullName
                }
            }
            elseif (Test-Path $p -PathType Leaf) {
                # Path is a specific file
                $allFiles += (Resolve-Path $p).Path
            }
            else {
                Write-Warning "Path not found: $p"
            }
        }
    }
}

end {
    if ($allFiles.Count -eq 0) {
        Write-Warning "No .cs files found to process."
        Write-Host "Usage examples:" -ForegroundColor Cyan
        Write-Host "  .\CSharpXmlDocsRemover.ps1 -Path '*.cs'" -ForegroundColor Gray
        Write-Host "  .\CSharpXmlDocsRemover.ps1 -Path 'src' -Recursive" -ForegroundColor Gray
        Write-Host "  .\CSharpXmlDocsRemover.ps1 -Path 'MyClass.cs'" -ForegroundColor Gray
        exit 1
    }

    # Build arguments
    $args = @()
    if ($DryRun) { $args += "--dry-run" }
    if ($VerbosePreference -eq 'Continue') { $args += "--verbose" }
    $args += $allFiles

    # Run the tool
    & dotnet $exePath $args

    exit $LASTEXITCODE
}
