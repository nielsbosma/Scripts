param(
    [switch]$GetPrompt,
    [switch]$GetTaskPrompt
)

. "$PSScriptRoot\.shared\Utils.ps1"

$programFolder = GetProgramFolder $PSCommandPath

$args = CollectArgs $args
# Args are REQUIRED here — must describe the feature to test

$logFile = GetNextLogFile $programFolder
$args | Set-Content $logFile

$promptFile = PrepareFirmware $PSScriptRoot $logFile $programFolder @{ Args = $args; WorkDir = (Get-Location).Path }

InvokeOrOutputPrompt $programFolder $promptFile $args $logFile -GetPrompt:$GetPrompt -GetTaskPrompt:$GetTaskPrompt
