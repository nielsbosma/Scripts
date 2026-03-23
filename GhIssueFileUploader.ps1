param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$IssueUrl,

    [Parameter(Mandatory = $true, Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Files
)

# Resolve file paths relative to caller's location
$resolvedFiles = $Files | ForEach-Object { Resolve-Path $_ -ErrorAction Stop }

node "$PSScriptRoot/GhIssueFileUploader/index.mjs" $IssueUrl @resolvedFiles
