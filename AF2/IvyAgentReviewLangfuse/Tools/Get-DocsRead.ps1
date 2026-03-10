<#
.SYNOPSIS
    Extracts all IvyDocs requests and responses from langfuse data.
.DESCRIPTION
    IvyDocs data comes in pairs:
    - Request: EVENT__local__IvyDocs files with input.path and input.content
    - Response: EVENT_LocalResponse files with input.toolName="IvyDocs" and input.response
.PARAMETER LangfuseDir
    Path to the langfuse data folder.
.OUTPUTS
    Array of objects: TraceName, Path, Success, ContentLength, Error
#>
param(
    [Parameter(Mandatory)][string]$LangfuseDir
)

$traceFolders = Get-ChildItem -Path $LangfuseDir -Directory | Sort-Object Name
$results = @()

foreach ($traceFolder in $traceFolders) {
    $obsFiles = Get-ChildItem -Path $traceFolder.FullName -Filter "*.json" |
        Where-Object { $_.Name -ne "trace.json" } | Sort-Object Name

    $pendingPath = $null

    foreach ($file in $obsFiles) {
        try {
            $json = Get-Content $file.FullName -Raw | ConvertFrom-Json
            $input = $json.input
            if (-not $input) { continue }

            # IvyDocs request: file name contains "IvyDocs" and input has path
            if ($file.Name -match 'IvyDocs' -and $input.path) {
                $pendingPath = $input.path
                continue
            }

            # IvyDocs response: LocalResponse with toolName=IvyDocs
            if ($input.toolName -eq 'IvyDocs' -and $input.response -and $pendingPath) {
                $results += [PSCustomObject]@{
                    TraceName     = $traceFolder.Name
                    Path          = $pendingPath
                    Success       = $input.response.success -eq $true
                    ContentLength = $input.response.contentLength
                    Error         = $input.response.error
                }
                $pendingPath = $null
            }
        } catch {}
    }
}

return $results
