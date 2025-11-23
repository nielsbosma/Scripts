# C# XML Documentation Remover

A Roslyn-based tool that precisely removes C# XML documentation comments from source files.

## Features

- **Precise removal** using Roslyn's syntax tree (no regex risks)
- Removes both `///` single-line and `/** */` multi-line XML documentation
- **Preserves** regular comments (`//` and `/* */`)
- **Wildcard support** - use patterns like `*.cs` or `src/*.cs`
- **Recursive directory processing** with `-Recursive` flag
- **Batch processing** support via PowerShell pipeline
- **Dry-run mode** to preview changes before applying
- UTF-8 encoding preservation

## Requirements

- .NET 8.0 SDK
- PowerShell 7+ (for the wrapper script)

## Installation

The tool will automatically build on first use. To manually build:

```bash
dotnet build CSharpXmlDocsRemover.csproj
```

## Usage

### Path Options

The `-Path` parameter supports multiple formats:

| Format | Description | Example |
|--------|-------------|---------|
| Single file | Process one specific file | `MyClass.cs` |
| Wildcard | Process all matching files in directory | `*.cs` or `src/*.cs` |
| Directory | Process all .cs files in directory | `src` |
| Directory + `-Recursive` | Process all .cs files in directory and subdirectories | `src -Recursive` |
| Wildcard + `-Recursive` | Process all matching files recursively | `src/*.cs -Recursive` |

### PowerShell Script (Recommended)

```powershell
# Single file
.\CSharpXmlDocsRemover.ps1 -Path "MyClass.cs"

# All .cs files in current directory using wildcard
.\CSharpXmlDocsRemover.ps1 -Path "*.cs"

# All .cs files in a directory (non-recursive)
.\CSharpXmlDocsRemover.ps1 -Path "src"

# All .cs files in a directory and subdirectories (recursive)
.\CSharpXmlDocsRemover.ps1 -Path "src" -Recursive

# Wildcard with recursive search
.\CSharpXmlDocsRemover.ps1 -Path "src/*.cs" -Recursive

# Batch process all .cs files using pipeline
Get-ChildItem -Path "src" -Recurse -Filter "*.cs" | .\CSharpXmlDocsRemover.ps1

# Dry run to see what would be removed
.\CSharpXmlDocsRemover.ps1 -Path "src" -Recursive -DryRun

# With verbose output
.\CSharpXmlDocsRemover.ps1 -Path "*.cs" -Verbose

# Batch with dry-run and verbose
.\CSharpXmlDocsRemover.ps1 -Path "src" -Recursive -DryRun -Verbose
```

### Direct C# Tool Usage

```bash
# Single file
dotnet run --project CSharpXmlDocsRemover -- "MyClass.cs"

# Multiple files
dotnet run --project CSharpXmlDocsRemover -- "File1.cs" "File2.cs" "File3.cs"

# Dry run
dotnet run --project CSharpXmlDocsRemover -- "MyClass.cs" --dry-run

# Verbose output
dotnet run --project CSharpXmlDocsRemover -- "MyClass.cs" --verbose
```

## What Gets Removed

The tool targets these specific Roslyn trivia kinds:
- `SingleLineDocumentationCommentTrivia` (the `///` comments)
- `MultiLineDocumentationCommentTrivia` (the `/** */` XML comments)

## What Gets Preserved

- Regular single-line comments (`//`)
- Regular multi-line comments (`/* */`)
- All code structure and formatting
- File encoding (UTF-8)

## Example

**Before:**
```csharp
/// <summary>
/// A test class
/// </summary>
public class MyClass
{
    // Regular comment - kept
    private string _value;

    /// <summary>
    /// Gets or sets the value
    /// </summary>
    public string Value { get; set; }

    /**
     * <summary>
     * Multi-line XML docs
     * </summary>
     */
    public void DoSomething()
    {
        /* Multi-line regular comment - kept */
    }
}
```

**After:**
```csharp
public class MyClass
{
    // Regular comment - kept
    private string _value;

    public string Value { get; set; }

    public void DoSomething()
    {
        /* Multi-line regular comment - kept */
    }
}
```

## How It Works

1. Parses each .cs file using `CSharpSyntaxTree.ParseText`
2. Walks through all syntax trivia nodes
3. Identifies and removes XML documentation trivia
4. Writes the modified syntax tree back to the file

This approach is safe because Roslyn represents doc comments as structured trivia, eliminating the risk of regex-based corruption.
