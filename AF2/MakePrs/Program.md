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

#### Search for Related GitHub Issues

After grouping commits, for each group:
1. Determine the repo's GitHub `owner/repo` from the git remote URL (`git remote get-url origin`)
2. Extract keywords from the proposed PR title (strip common prefixes like "Add", "Fix", "Update", "Refactor")
3. Search for open issues in that repo:
   ```bash
   gh search issues "<keywords>" --repo <owner/repo> --state open --json title,url,number,body --limit 10
   ```
4. Also search using keywords extracted from commit messages
5. Parse commit messages for existing issue references (e.g., `#123`) and include those automatically
6. Deduplicate results and store the matched issues per group

### 4. Present Plan to User

**Enter plan mode** (using the EnterPlanMode tool) and present the PR groups as a plan. Each group should show:
- Proposed PR title
- Repository
- List of commits (short hash + subject)
- Estimated base branch (usually origin/main or origin/master)
- Linked issues (if any were found in the GitHub issue search or referenced in commit messages). Omit the `Links:` line if no relevant issues exist.

Example plan format:
```
PR 1: [Ivy-Framework] Add RadialBarChart widget
  Base: origin/main
  Commits:
    - abc1234 Add RadialBarChart backend widget class
    - def5678 Add RadialBarChart frontend component
  Links:
    - https://github.com/Ivy-Interactive/Ivy-Framework/issues/42 Add RadialBarChart widget support
    - https://github.com/Ivy-Interactive/Ivy-Framework/issues/38 Missing chart types

PR 2: [Ivy-Agent] Refactor session management
  Base: origin/main
  Commits:
    - jkl3456 Refactor session management
    - mno7890 Add timeout configuration
```

Not every PR group will have related issues — that's fine. Group commits logically by functionality regardless of whether matching issues exist.

The user can review, modify, or remove groups before approving. Once the user approves the plan, exit plan mode and only execute on the PR groups that remain in the approved plan.

### 5. Create Pull Requests

For each approved group that remains in the plan:

#### A. Get PR Details from User
- **PR Title** (suggest from commits, allow editing)
- **PR Body** (generate summary from commits, allow editing)
  - If issues were linked in Step 4, append `Closes #N` lines to the body (one per linked issue)
  - For cross-repo issues, use full URL syntax: `Closes Ivy-Interactive/Ivy-Framework#42`
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
2. Build the PR body with summary and issue references:
   ```markdown
   ## Summary
   <generated summary from commits>

   Closes #42
   Closes #38
   ```
3. Create PR using gh CLI:
   ```powershell
   gh pr create --repo [repo-url] --head [branch-name] --base [base-branch] --title "[title]" --body "[body-with-closes-refs]"
   ```
4. If assignee specified, assign PR: `gh pr edit [pr-url] --add-assignee [assignee]`
5. **IMPORTANT**: Open PR URL in browser using `Start-Process [pr-url]` (PowerShell) or appropriate browser launch command
6. **Ask user**: "Drop these commits from [original-branch]? (y/n)"
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
- `-AutoApprove`: Skip approval prompt and create all suggested PRs automatically. For issue linking, automatically link all issues whose title has high similarity (>70%) to the PR title
- `-AutoAssign [user]`: Automatically assign all PRs to the specified user
- `-SkipUncommitted`: Skip the uncommitted changes check and only work with committed changes
- `-Repo [name]`: Only process the specified repository (e.g., `-Repo Ivy-Framework`)

## Error Handling

- If no unpushed commits found, inform user and exit gracefully
- If git commands fail, show error and continue with other repos
- If cherry-pick conflicts occur, abort and skip that PR
- If gh CLI not available, error and exit (gh is required)
- If repo not found, skip it with a warning
- If `gh search issues` fails or returns no results, skip issue linking silently for that group
- If issue search returns results but none are relevant, skip the linking prompt

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
