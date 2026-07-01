param([Parameter(ValueFromRemainingArguments)][string[]]$Args)

Set-Location "D:\Repos\_Ivy\Ivy-Tendril"

if ($Args.Count -gt 0) {
    claude --dangerously-skip-permissions -- "start planning:$($Args -join ' ')"
} else {
    claude --dangerously-skip-permissions -- "start planning and ask for task"
}
