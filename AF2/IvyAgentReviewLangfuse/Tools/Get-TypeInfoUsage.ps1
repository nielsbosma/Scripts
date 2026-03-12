<#
.SYNOPSIS
    Extracts all GetTypeInfo requests and responses from langfuse data.
.DESCRIPTION
    GetTypeInfo data comes in pairs:
    - Request: EVENT__local__GetTypeInfo files with input.search
    - OR: GENERATION output containing tool call with name=GetTypeInfo
    - Response: EVENT_LocalResponse files with input.toolName="GetTypeInfo" and input.response

    For each response, matches to the request using messageId/responseTo correlation,
    falling back to nearest preceding unmatched request if messageId is unavailable.
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
        # EVENT GetTypeInfoMessage with input.message.search or input.search
        if ($obs.File.Name -match 'GetTypeInfo' -and -not ($obs.File.Name -match 'Result')) {
            $search = $obs.Json.input.message.search
            if (-not $search) { $search = $obs.Json.input.search }
            if ($search) {
                $searchType = $obs.Json.input.message.searchType
                if (-not $searchType) { $searchType = $obs.Json.input.searchType }
                $maxResults = $obs.Json.input.message.maxResults
                if (-not $maxResults) { $maxResults = $obs.Json.input.maxResults }
                $messageId = $obs.Json.input.message.messageId
                $requests += [PSCustomObject]@{
                    Index      = $i
                    Search     = $search
                    SearchType = $searchType
                    MaxResults = $maxResults
                    Source     = 'EVENT'
                    Matched    = $false
                    MessageId  = $messageId
                }
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
                        MessageId  = $null
                    }
                }
            }
        }
    }

    # Deduplicate: if an EVENT and GENERATION have the same search at the same index range, keep only the EVENT
    $deduped = [System.Collections.Generic.List[object]]::new()
    $seenSearches = @{}
    foreach ($req in ($requests | Sort-Object Index)) {
        $key = "$($req.Search)|$($req.SearchType)"
        $isEvent = $req.Source -eq 'EVENT'

        if ($seenSearches.ContainsKey($key)) {
            $existing = $seenSearches[$key]
            $existingIsEvent = $existing.Source -eq 'EVENT'
            # Keep EVENT over GENERATION
            if ($isEvent -and -not $existingIsEvent) {
                $toRemove = @($deduped | Where-Object { "$($_.Search)|$($_.SearchType)" -eq $key -and $_.Source -eq 'GENERATION' })
                foreach ($r in $toRemove) { $deduped.Remove($r) | Out-Null }
                $deduped.Add($req)
                $seenSearches[$key] = $req
            }
            # If both are events with same search (re-search), keep both
            elseif ($isEvent -and $existingIsEvent) {
                $deduped.Add($req)
            }
            # Otherwise skip (duplicate from generation)
        } else {
            $deduped.Add($req)
            $seenSearches[$key] = $req
        }
    }
    $requests = @($deduped | Sort-Object Index)

    # For each response, match to nearest preceding unmatched request
    for ($i = 0; $i -lt $observations.Count; $i++) {
        $obs = $observations[$i]
        $input = $obs.Json.input
        if (-not $input) { continue }
        # Match both old format (input.toolName/input.response) and new format (input.message.$type=GetTypeInfoResultMessage)
        $isOldFormat = ($input.toolName -eq 'GetTypeInfo' -and $input.response)
        $isNewFormat = ($input.message -and $input.message.'$type' -eq 'GetTypeInfoResultMessage')
        if (-not $isOldFormat -and -not $isNewFormat) { continue }
        # Normalize: for new format, use input.message as the response data
        $responseData = if ($isNewFormat) { $input.message } else { $input.response }

        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($obs.File.Name)

        # Match response to request by messageId correlation, fall back to index-based
        $matchedReq = $null
        $responseTo = $responseData.responseTo
        if (-not $responseTo) { $responseTo = $input.message.responseTo }
        if ($responseTo) {
            $matchedReq = $requests | Where-Object { $_.MessageId -eq $responseTo -and -not $_.Matched } | Select-Object -First 1
        }
        if (-not $matchedReq) {
            # Fall back: nearest preceding unmatched request
            foreach ($req in $requests) {
                if ($req.Index -lt $i -and -not $req.Matched) {
                    $matchedReq = $req
                }
                if ($req.Index -ge $i) { break }
            }
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
        if ($responseData.types -is [array]) {
            $names = @()
            foreach ($t in $responseData.types) {
                if ($t.Name) { $names += $t.Name }
                elseif ($t.name) { $names += $t.name }
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
            Success         = $responseData.success -eq $true
            TotalMatches    = $responseData.totalMatches
            TypeNames       = $typeNames
            Error           = $responseData.errorMessage
            Warning         = $responseData.warningMessage
        }
    }
}

return $results
