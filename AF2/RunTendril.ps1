param([Parameter(ValueFromRemainingArguments)][string[]]$Args)

Get-Process -Name "Ivy.Tendril" -ErrorAction SilentlyContinue | Stop-Process -Force

Set-Location "D:\Repos\_Ivy\Ivy-Tendril\src\Ivy.Tendril"
if ($Args.Count -gt 0) {
    dotnet run -- @Args --find-available-port --browse --enable-dev-tools
} else {
    dotnet run -- --find-available-port --browse --enable-dev-tools
}
