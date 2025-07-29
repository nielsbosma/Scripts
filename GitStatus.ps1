$allStatuses = @()

Get-ChildItem -Directory | ForEach-Object {
    Set-Location -Path $_.FullName
    if ((Test-Path .git) -or (Get-Command git -ErrorAction SilentlyContinue)) {
        git fetch --prune --quiet
        # Get current branch
        $branch = git branch --show-current 2>$null
        if ($branch) {
            # Get upstream tracking info
            $upstream = git rev-list --count "HEAD..@{u}" 2>$null
            $behind = git rev-list --count "@{u}..HEAD" 2>$null
            
            # Create custom object for table
            $status = [PSCustomObject]@{
                Repository = $_.Name
                Branch = $branch
                Ahead = if ($upstream -and $upstream -ne "") { "+$upstream" } else { "0" }
                Behind = if ($behind -and $behind -ne "") { "-$behind" } else { "0" }
            }
            $allStatuses += $status
        } else {
            $status = [PSCustomObject]@{
                Repository = $_.Name
                Branch = "N/A"
                Ahead = "N/A"
                Behind = "N/A"
            }
            $allStatuses += $status
        }
    }
    Set-Location -Path ..
}

$allStatuses | Format-Table -AutoSize