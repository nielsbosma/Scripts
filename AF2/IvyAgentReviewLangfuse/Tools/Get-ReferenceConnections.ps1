<#
.SYNOPSIS
    Extracts reference connection usage from langfuse data.
    Looks for WorkflowReferenceMessage/WorkflowReferenceResultMessage events that reference connections.
.PARAMETER LangfuseDir
    Path to the langfuse data folder.
.PARAMETER ConnectionsDir
    Path to the connections directory. Default: D:\Repos\_Ivy\Ivy\connections
.OUTPUTS
    Array of objects: ReferenceName, LocalPath, Success, ContentChars
#>
param(
    [Parameter(Mandatory)][string]$LangfuseDir,
    [string]$ConnectionsDir = "D:\Repos\_Ivy\Ivy\connections"
)

$traceFolders = Get-ChildItem -Path $LangfuseDir -Directory | Sort-Object Name
$connectionRefs = @{}

foreach ($traceFolder in $traceFolders) {
    $obsFiles = Get-ChildItem -Path $traceFolder.FullName -Filter "*.json" |
        Where-Object { $_.Name -ne "trace.json" } | Sort-Object Name

    foreach ($file in $obsFiles) {
        try {
            $json = Get-Content $file.FullName -Raw | ConvertFrom-Json

            # Check both input.message (old format) and metadata.message (new format)
            $message = $null
            if ($json.input -and $json.input.message) {
                $message = $json.input.message
            } elseif ($json.metadata -and $json.metadata.message) {
                $message = $json.metadata.message
            }

            if (-not $message -or -not $message.'$type') { continue }

            $msgType = $message.'$type'

            if ($msgType -eq 'WorkflowReferenceMessage') {
                $name = $message.name
                if ($name -and -not $connectionRefs.ContainsKey($name)) {
                    $connectionRefs[$name] = [PSCustomObject]@{
                        ReferenceName = $name
                        LocalPath = $null
                        Success = $null
                        ContentChars = $null
                    }
                }
            }
            elseif ($msgType -eq 'WorkflowReferenceResultMessage') {
                $name = $message.name
                if ($name) {
                    $success = $message.success -eq $true
                    $contentLen = if ($message.content) { $message.content.Length } else { $null }

                    if ($connectionRefs.ContainsKey($name)) {
                        $connectionRefs[$name].Success = $success
                        $connectionRefs[$name].ContentChars = $contentLen
                    } else {
                        $connectionRefs[$name] = [PSCustomObject]@{
                            ReferenceName = $name
                            LocalPath = $null
                            Success = $success
                            ContentChars = $contentLen
                        }
                    }
                }
            }
        } catch {}
    }
}

# Resolve local paths for connections
foreach ($ref in $connectionRefs.Values) {
    $name = $ref.ReferenceName
    # Try to find matching connection folder
    if (Test-Path $ConnectionsDir) {
        $match = Get-ChildItem -Path $ConnectionsDir -Directory | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($match) {
            $ref.LocalPath = $match.FullName
        } else {
            # Try case-insensitive partial match
            $match = Get-ChildItem -Path $ConnectionsDir -Directory | Where-Object { $_.Name -like "*$name*" } | Select-Object -First 1
            if ($match) { $ref.LocalPath = $match.FullName }
        }
    }
}

return $connectionRefs.Values | Sort-Object ReferenceName
