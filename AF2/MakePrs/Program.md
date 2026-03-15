# MakePrs

Analyze unpushed commits across Ivy repositories and create logical pull requests.

## Context

We have the following repositories on this machine:

Read ../.shared/Repos.md

This tool helps organize unpushed commits into logical PRs by:
1. Checking for uncommitted changes (and optionally committing them)
2. Analyzing all unpushed commits across repositories
3. Grouping commits into logical PR proposals
4. Creating PRs via cherry-picking commits to new branches

## Execution Steps

### 1. Check for Uncommitted Changes

For each repository in Repos.md:
- Run `git status --porcelain` to check for uncommitted changes
- If uncommitted changes exist:
  - **Prompt user**: "Repository [repo-name] has uncommitted changes. Commit them now? (y/n)"
  - If yes, create a commit inspired by Sync.ps1:
    - Run `git status` to see files
    - Run `git diff` to see changes
    - Run `git log --oneline -5` to see recent commit style
    - Analyze changes and create a logical commit message
    - Stage appropriate files (avoid .env, credentials, large binaries)
    - Create commit with: `Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>`
  - If no, warn that this repo will be skipped for PR creation

### 2. Gather Unpushed Commits

For each repository:
- Get current branch: `git rev-parse --abbrev-ref HEAD`
- Check if remote tracking branch exists: `git rev-parse --verify origin/[branch]`
- Get unpushed commits: `git log origin/[branch]..HEAD --format=%H|%s|%an|%ci` (or all commits if no remote tracking branch)
- Collect commit data: hash, subject, author, date, repo, branch

### 3. Analyze and Group Commits

Using the collected commits, analyze them to suggest logical PR groupings based on:
- Related functionality (e.g., all commits about a specific feature)
- Same repository and functional area
- Temporal proximity (commits made around the same time often relate)
- Commit message patterns (look for related keywords)

Create a PR plan with groups like:
```
PR Group 1: [Ivy-Framework] Add RadialBarChart widget
  - Commits: 3 commits
  - abc1234 Add RadialBarChart backend widget class
  - def5678 Add RadialBarChart frontend component
  - ghi9012 Add RadialBarChart sample and docs

PR Group 2: [Ivy-Agent] Fix session timeout handling
  - Commits: 2 commits
  - jkl3456 Refactor session management
  - mno7890 Add timeout configuration
```

### 4. Present Plan to User

Display the suggested PR plan with:
- Number of groups
- Each group showing:
  - Proposed PR title
  - Repository
  - List of commits (short hash + subject)
  - Estimated base branch (usually origin/main or origin/master)

Ask user for approval:
```
Options:
  a) Approve all and create PRs
  1-N) Review/modify group N
  c) Cancel
```

### 5. Create Pull Requests

For each approved group:

#### A. Get PR Details from User
- **PR Title** (suggest from commits, allow editing)
- **PR Body** (generate summary from commits, allow editing)
- **Base Branch** (suggest origin/main, allow changing)
- **Assignee** (optional):
  - None (leave unassigned)
  - @me (assign to self)
  - @copilot (assign to GitHub Copilot)
  - [username] (specific GitHub username)

#### B. Create Branch and Cherry-pick
Follow the pattern from ReviewCommits.ps1:
1. Derive branch name from PR title: `pr/[short-hash]-[sanitized-title]`
2. Get default branch for the repo
3. Remember current branch to restore later
4. Delete any leftover local branch from previous attempt
5. Create new branch off default branch: `git branch [branch-name] origin/[default-branch]`
6. Checkout new branch: `git checkout [branch-name]`
7. Cherry-pick commits in order: `git cherry-pick [hash1] [hash2] ...`
   - If cherry-pick fails, show error, abort, cleanup, and skip this PR
8. Return to original branch: `git checkout [original-branch]`

#### C. Push and Create PR
1. Push branch to origin: `git push -u origin [branch-name]`
2. Create PR using gh CLI:
   ```powershell
   gh pr create --repo [repo-url] --head [branch-name] --base [base-branch] --title "[title]" --body "[body]"
   ```
3. If assignee specified, assign PR: `gh pr edit [pr-url] --add-assignee [assignee]`
4. **IMPORTANT**: Open PR URL in browser using `Start-Process [pr-url]` (PowerShell) or appropriate browser launch command
5. **Ask user**: "Drop these commits from [original-branch]? (y/n)"
   - If yes, drop commits using rebase: `git rebase --onto [first-hash]^ [last-hash] [original-branch]`
   - If rebase fails, warn user and abort rebase

#### D. Handle Errors
- Track which PRs succeeded and which failed
- For failures, show clear error messages
- Don't clean up failed branches automatically (user may want to investigate)

### 6. Summary

Display final summary:
```
✓ Created 3 PRs successfully
  - [url1]
  - [url2]
  - [url3]

✗ Failed to create 1 PR
  - [repo-name] [branch-name]: [error message]
```

## Args Flags

Parse Args for optional flags:
- `-AutoApprove`: Skip approval prompt and create all suggested PRs automatically
- `-AutoAssign [user]`: Automatically assign all PRs to the specified user
- `-SkipUncommitted`: Skip the uncommitted changes check and only work with committed changes
- `-Repo [name]`: Only process the specified repository (e.g., `-Repo Ivy-Framework`)

## Error Handling

- If no unpushed commits found, inform user and exit gracefully
- If git commands fail, show error and continue with other repos
- If cherry-pick conflicts occur, abort and skip that PR
- If gh CLI not available, error and exit (gh is required)
- If repo not found, skip it with a warning

## Tools

Store reusable PowerShell functions in Tools/ such as:
- `Get-UnpushedCommits.ps1` - Get unpushed commits for a repo
- `New-PrBranch.ps1` - Create and cherry-pick commits to new branch
- `Group-CommitsByTopic.ps1` - Smart grouping logic

## Notes

- Always validate that gh CLI is installed: `Get-Command gh -ErrorAction SilentlyContinue`
- Use `git config --global diff.tool vscode` for consistent diff viewing if needed
- Respect git hooks and signing - never use --no-verify or --no-gpg-sign
- If a PR creation fails, continue with remaining PRs
- Cherry-picking preserves original commit authors and messages
