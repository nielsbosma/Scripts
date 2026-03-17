# MakePrs Usage Guide

## Quick Start

```powershell
# Basic usage - analyze and create PRs interactively
D:\Repos\_Personal\Scripts\AF2\MakePrs.ps1

# Skip uncommitted changes check
D:\Repos\_Personal\Scripts\AF2\MakePrs.ps1 -SkipUncommitted

# Auto-approve all suggested PRs
D:\Repos\_Personal\Scripts\AF2\MakePrs.ps1 -AutoApprove

# Auto-assign PRs to GitHub Copilot
D:\Repos\_Personal\Scripts\AF2\MakePrs.ps1 -AutoAssign copilot

# Process only Ivy-Framework repository
D:\Repos\_Personal\Scripts\AF2\MakePrs.ps1 -Repo Ivy-Framework

# Combined: auto-approve and assign
D:\Repos\_Personal\Scripts\AF2\MakePrs.ps1 -AutoApprove -AutoAssign @me
```

## Workflow

1. **Uncommitted Changes Check**: Tool checks each repo for uncommitted files
   - Prompts to commit them (can skip with `-SkipUncommitted`)
   - Creates logical commits inspired by Sync.ps1

2. **Commit Analysis**: Gathers all unpushed commits across repositories
   - Fetches all open issues from each repo's GitHub for smart matching
   - Matches commits to issues using three phases:
     - **Explicit references**: `#123`, `Fixes #123`, etc. → auto-matched
     - **Smart matching**: Keyword, file path, label, and title similarity scoring (0-100)
       - Score ≥ 70: auto-matched
       - Score 40-69: suggested to user for approval
       - Score < 40: unmatched
     - **Feature grouping**: Unmatched commits grouped by file path/keyword similarity

3. **PR Plan Presentation**: Shows suggested PR groupings
   - Each group includes commit list and proposed title
   - User can review, modify, or skip groups

4. **PR Creation**: For approved groups:
   - Creates new branch from main/master
   - Cherry-picks commits to preserve authorship
   - Pushes branch and creates PR via gh CLI
   - Optionally assigns reviewers
   - Optionally drops commits from original branch

## Flags Reference

| Flag | Description |
|------|-------------|
| `-AutoApprove` | Skip plan approval; still prompts for suggested matches (40-69) |
| `-AutoApproveAll` | Skip all prompts including suggested match approval |
| `-AutoAssign [user]` | Automatically assign PRs to specified user (@me, copilot, username) |
| `-SkipUncommitted` | Skip uncommitted changes check |
| `-Repo [name]` | Only process specified repository |

## Integration with Other AF2 Components

- **ReviewCommits**: Shares cherry-pick pattern for creating PR branches
- **Sync**: Shares commit creation logic for uncommitted changes
- **BuildApproved**: Could trigger MakePrs after successful builds
- **MakePlan**: Could reference PRs created by this tool

## Requirements

- Git installed and configured
- GitHub CLI (`gh`) installed and authenticated
- Access to Ivy repositories listed in ../.shared/Repos.md
