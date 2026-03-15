param(
    [switch]$GetPrompt,
    [switch]$GetTaskPrompt
)

. "$PSScriptRoot\.shared\Utils.ps1"

$programFolder = GetProgramFolder $PSCommandPath

$args = CollectArgs $args
# Args are REQUIRED here — must describe the feature to test

# Set terminal tab title to feature name (smart extraction from args)
$titleName = if ($args -match '[/\\]([^/\\]+)[\\/]?$') { $Matches[1] }
             elseif ($args -match 'Commit\s+\w+:\s*(.+?)(?:\.|$)') { $Matches[1].Trim() }
             else { $args.Substring(0, [Math]::Min(50, $args.Length)) }
Write-Host "`e]0;IFT: $titleName`a" -NoNewline

$logFile = GetNextLogFile $programFolder
$args | Set-Content $logFile

$promptFile = PrepareFirmware $PSScriptRoot $logFile $programFolder @{ Args = $args; WorkDir = (Get-Location).Path }

InvokeOrOutputPrompt $programFolder $promptFile $args $logFile -GetPrompt:$GetPrompt -GetTaskPrompt:$GetTaskPrompt
