<#
.SYNOPSIS
    Extracts all IvyDocs requests and responses from langfuse data.
.DESCRIPTION
    IvyDocs data comes in pairs:
    - Request: EVENT__local__IvyDocs files with input.path
    - OR: GENERATION output containing tool call with name=IvyDocs (when no separate event exists)
    - Response: EVENT_LocalResponse files with input.toolName="IvyDocs" and input.response

    For each response, walks backwards to find the nearest unmatched request.
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

    # Load all observations
    $observations = @()
    foreach ($file in $obsFiles) {
        try {
            $json = Get-Content $file.FullName -Raw | ConvertFrom-Json
            $observations += [PSCustomObject]@{ File = $file; Json = $json }
        } catch {}
    }

    # Collect all IvyDocs request paths with their indices
    $requests = @() # array of @{Index; Path; Matched}
    for ($i = 0; $i -lt $observations.Count; $i++) {
        $obs = $observations[$i]
        # EVENT__local__IvyDocs - check input.path (old) and metadata.path (new)
        if ($obs.File.Name -match 'IvyDocs' -and -not ($obs.File.Name -match 'LocalResponse')) {
            $path = $null
            if ($obs.Json.input -and $obs.Json.input.path) {
                $path = $obs.Json.input.path
            } elseif ($obs.Json.metadata -and $obs.Json.metadata.path) {
                $path = $obs.Json.metadata.path
            }
            if ($path) {
                $requests += [PSCustomObject]@{ Index = $i; Path = $path; Matched = $false }
            }
        }
        # GENERATION output with IvyDocs tool call
        if ($obs.File.Name -match 'GENERATION' -and $obs.Json.output -is [array]) {
            foreach ($tc in $obs.Json.output) {
                if ($tc.name -eq 'IvyDocs' -and $tc.arguments.path) {
                    $requests += [PSCustomObject]@{ Index = $i; Path = $tc.arguments.path; Matched = $false }
                }
            }
        }
    }

    # Deduplicate: if an EVENT and GENERATION have the same path, keep only the EVENT
    $deduped = @()
    $seenPaths = @{}
    foreach ($req in ($requests | Sort-Object Index)) {
        $obs = $observations[$req.Index]
        $isEvent = $obs.File.Name -match 'EVENT'
        $key = $req.Path

        if ($seenPaths.ContainsKey($key)) {
            $existing = $seenPaths[$key]
            $existingObs = $observations[$existing.Index]
            $existingIsEvent = $existingObs.File.Name -match 'EVENT'
            # Keep EVENT over GENERATION
            if ($isEvent -and -not $existingIsEvent) {
                $deduped = @($deduped | Where-Object { $_.Path -ne $key })
                $deduped += $req
                $seenPaths[$key] = $req
            }
            # If both are events with same path (re-read), keep both
            elseif ($isEvent -and $existingIsEvent) {
                $deduped += $req
            }
            # Otherwise skip (duplicate from generation)
        } else {
            $deduped += $req
            $seenPaths[$key] = $req
        }
    }
    $requests = $deduped | Sort-Object Index

    # For each response, match to nearest preceding unmatched request
    for ($i = 0; $i -lt $observations.Count; $i++) {
        $obs = $observations[$i]
        # Check both input (old) and metadata (new) for LocalResponse with IvyDocs
        $toolName = $null
        $response = $null
        if ($obs.Json.input -and $obs.Json.input.toolName) {
            $toolName = $obs.Json.input.toolName
            $response = $obs.Json.input.response
        } elseif ($obs.Json.metadata -and $obs.Json.metadata.toolName) {
            $toolName = $obs.Json.metadata.toolName
            $response = $obs.Json.metadata.response
        }
        if ($toolName -ne 'IvyDocs' -or -not $response) { continue }

        # Find nearest preceding unmatched request
        $matchedReq = $null
        foreach ($req in $requests) {
            if ($req.Index -lt $i -and -not $req.Matched) {
                $matchedReq = $req
                # Don't break - we want the latest unmatched request before this response
            }
            if ($req.Index -ge $i) { break }
        }

        $path = '(unknown)'
        if ($matchedReq) {
            $path = $matchedReq.Path
            $matchedReq.Matched = $true
        }

        $results += [PSCustomObject]@{
            TraceName     = $traceFolder.Name
            Path          = $path
            Success       = $response.success -eq $true
            ContentLength = $response.contentLength
            Error         = $response.error
        }
    }
}

return $results
