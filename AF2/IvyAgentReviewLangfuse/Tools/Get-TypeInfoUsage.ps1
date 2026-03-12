<#
.SYNOPSIS
    Extracts all GetTypeInfo requests and responses from langfuse data.
.DESCRIPTION
    GetTypeInfo data comes in pairs:
    - Request: EVENT__local__GetTypeInfo files with input.search
    - OR: GENERATION output containing tool call with name=GetTypeInfo
    - Response: EVENT_LocalResponse files with input.toolName="GetTypeInfo" and input.response

    For each response, walks backwards to find the nearest unmatched request.
.PARAMETER LangfuseDir
    Path to the langfuse data folder.
.OUTPUTS
    Array of objects: TraceName, ObservationFile, Search, SearchType, MaxResults, Success, TotalMatches, TypeNames, Error, Warning
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

    # Collect all GetTypeInfo request entries with their indices
    $requests = @() # array of @{Index; Search; SearchType; MaxResults; Source; Matched}
    for ($i = 0; $i -lt $observations.Count; $i++) {
        $obs = $observations[$i]
        # EVENT__local__GetTypeInfo with input.search
        if ($obs.File.Name -match 'GetTypeInfo' -and $obs.Json.input.search) {
            $requests += [PSCustomObject]@{
                Index      = $i
                Search     = $obs.Json.input.search
                SearchType = $obs.Json.input.searchType
                MaxResults = $obs.Json.input.maxResults
                Source     = 'EVENT'
                Matched    = $false
            }
        }
        # GENERATION output with GetTypeInfo tool call
        if ($obs.File.Name -match 'GENERATION' -and $obs.Json.output -is [array]) {
            foreach ($tc in $obs.Json.output) {
                if ($tc.name -eq 'GetTypeInfo' -and $tc.arguments.search) {
                    $requests += [PSCustomObject]@{
                        Index      = $i
                        Search     = $tc.arguments.search
                        SearchType = $tc.arguments.searchType
                        MaxResults = $tc.arguments.maxResults
                        Source     = 'GENERATION'
                        Matched    = $false
                    }
                }
            }
        }
    }

    # Deduplicate: if an EVENT and GENERATION have the same search, keep only the EVENT
    $deduped = @()
    $seenSearches = @{}
    foreach ($req in ($requests | Sort-Object Index)) {
        $key = "$($req.Search)|$($req.SearchType)"
        $isEvent = $req.Source -eq 'EVENT'

        if ($seenSearches.ContainsKey($key)) {
            $existing = $seenSearches[$key]
            $existingIsEvent = $existing.Source -eq 'EVENT'
            # Keep EVENT over GENERATION
            if ($isEvent -and -not $existingIsEvent) {
                $deduped = $deduped | Where-Object { "$($_.Search)|$($_.SearchType)" -ne $key }
                $deduped += $req
                $seenSearches[$key] = $req
            }
            # If both are events with same search (re-search), keep both
            elseif ($isEvent -and $existingIsEvent) {
                $deduped += $req
            }
            # Otherwise skip (duplicate from generation)
        } else {
            $deduped += $req
            $seenSearches[$key] = $req
        }
    }
    $requests = $deduped | Sort-Object Index

    # For each response, match to nearest preceding unmatched request
    for ($i = 0; $i -lt $observations.Count; $i++) {
        $obs = $observations[$i]
        $input = $obs.Json.input
        if (-not $input) { continue }
        if ($input.toolName -ne 'GetTypeInfo' -or -not $input.response) { continue }

        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($obs.File.Name)

        # Find nearest preceding unmatched request
        $matchedReq = $null
        foreach ($req in $requests) {
            if ($req.Index -lt $i -and -not $req.Matched) {
                $matchedReq = $req
                # Don't break - we want the latest unmatched request before this response
            }
            if ($req.Index -ge $i) { break }
        }

        $search = '(unknown)'
        $searchType = $null
        $maxResults = $null
        if ($matchedReq) {
            $search = $matchedReq.Search
            $searchType = $matchedReq.SearchType
            $maxResults = $matchedReq.MaxResults
            $matchedReq.Matched = $true
        }

        # Extract type names from response
        $typeNames = $null
        if ($input.response.types -is [array]) {
            $names = @()
            foreach ($t in $input.response.types) {
                if ($t.Name) { $names += $t.Name }
            }
            if ($names.Count -gt 0) {
                $typeNames = $names -join ', '
            }
        }

        $results += [PSCustomObject]@{
            TraceName       = $traceFolder.Name
            ObservationFile = $fileName
            Search          = $search
            SearchType      = $searchType
            MaxResults      = $maxResults
            Success         = $input.response.success -eq $true
            TotalMatches    = $input.response.totalMatches
            TypeNames       = $typeNames
            Error           = $input.response.errorMessage
            Warning         = $input.response.warningMessage
        }
    }
}

return $results
