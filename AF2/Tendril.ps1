param([Parameter(ValueFromRemainingArguments)][string[]]$Args)

Set-Location "D:\Repos\_Ivy\Ivy-Tendril\src\Ivy.Tendril"
if ($Args.Count -gt 0) {
    dotnet run @Args
} else {
    dotnet run -- --find-available-port --browse --enable-dev-tools
}
