. "$PSScriptRoot\.shared\Utils.ps1"

$args = CollectArgs $args

Write-Host "Arguments:"
for ($i = 0; $i -lt $args.Count; $i++) {
    Write-Host "  [$i]: $($args[$i])"
}
