param(
    [switch]$GetPrompt,
    [switch]$GetTaskPrompt,
    [switch]$Interactive
)

. "$PSScriptRoot\.shared\Utils.ps1"

$programFolder = GetProgramFolder $PSCommandPath

$args = CollectArgs $args

$logFile = GetNextLogFile $programFolder
$args | Set-Content $logFile
Write-Host "Log file: $logFile"

$promptFile = PrepareFirmware $PSScriptRoot $logFile $programFolder @{ Args = $args; WorkDir = (Get-Location).Path }

InvokeOrOutputPrompt $programFolder $promptFile $args $logFile -GetPrompt:$GetPrompt -GetTaskPrompt:$GetTaskPrompt -Interactive:$Interactive
