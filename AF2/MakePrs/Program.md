# MakePrs

Analyze unpushed commits across Ivy repositories and create logical pull requests.

## Context

We have the following repositories on this machine:

Read ../.shared/Repos.md

This tool helps organize unpushed commits into issue-based PRs by:
1. Checking for uncommitted changes (and optionally committing them)
2. Analyzing all unpushed commits across repositories
3. Fetching all open issues across repos for smart matching
4. Matching commits to issues (explicit references → smart matching → feature grouping)
5. Creating PRs via cherry-picking commits to new branches

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

### 2.5. Fetch All Open Issues

For each repository in Repos.md, fetch all open issues:

1. Determine `owner/repo` from the git remote URL: `git remote get-url origin`
2. Fetch open issues:
   ```bash
   gh issue list --repo <owner/repo> --state open --json number,title,body,labels,url --limit 100
   ```
3. Store issues with metadata: number, title, body, labels, URL, repo path, owner/repo

Skip repos where `gh issue list` fails (e.g., no GitHub remote). Issues are scoped per repo — a commit in Ivy-Framework should only match to Ivy-Framework issues, not Ivy-Agent issues.

### 3. Smart Commit-to-Issue Matching

Match commits to issues using a three-phase approach. Each commit is marked as "matched" once assigned to an issue group, preventing double-assignment.

#### Phase 1: Explicit References (High Confidence)

For each commit, extract explicit issue references from the commit message:
- Patterns: `#123`, `Fixes #123`, `Closes #123`, `Resolves #123` (case-insensitive)
- Cross-repo references: `Ivy-Interactive/Ivy-Framework#42`
- A commit may reference multiple issues — include it in each issue's group
- Mark these commits as "matched"

All commits referencing the same issue number (within the same repo) go into one group. Validate each referenced issue:
```bash
gh issue view <number> --repo <owner/repo> --json state,title,url
```
- Use the issue title to enhance the PR title
- If the issue doesn't exist or is closed, warn but still allow PR creation

#### Phase 2: Intelligent Matching (Medium Confidence)

For each **unmatched** commit, score it against all open issues **in the same repo**:

1. **Keyword Matching** (0-40 points):
   - Extract meaningful keywords from commit subject (strip common verbs: "fix", "add", "update", "remove", "refactor", "change")
   - Extract keywords from issue title and body
   - Score based on keyword overlap: `(matching_keywords / total_commit_keywords) * 40`

2. **File Path Matching** (0-30 points):
   - Get file paths changed in commit: `git show --name-only --format= <hash>`
   - Compare with file paths or component names mentioned in issue title/body
   - Score based on path overlap (e.g., both mention `Widgets/`, `RadialBarChart`, `Session`)
   - Partial path matches count (directory name match = 15, full file match = 30)

3. **Label Matching** (0-15 points):
   - If commit message contains "bug"/"fix" → boost match to issues labeled "bug"
   - If commit message contains "feature"/"feat" → boost match to issues labeled "enhancement"/"feature"
   - If commit message contains "docs"/"readme" → boost match to issues labeled "documentation"

4. **Title Similarity** (0-15 points):
   - Compare commit subject words against issue title words (case-insensitive)
   - Score: `(common_words / max(commit_words, title_words)) * 15`

**Matching Thresholds**:
- Score ≥ 70: **Auto-match** — commit is assigned to the highest-scoring issue
- Score 40-69: **Suggested match** — present to user for approval
- Score < 40: **No match** — commit moves to Phase 3

If a commit scores ≥ 70 on multiple issues, assign to the highest-scoring one. If tied, prefer the issue whose title most closely matches the commit subject.

#### Phase 3: Feature-Based Grouping (Unmatched Commits)

For commits that scored < 40 on all issues (or had no open issues in their repo):

1. **Group by file path similarity**: Commits touching the same directories or files go together
2. **Group by keyword similarity**: Commits with overlapping subject keywords go together
3. **Derive a group title**: Use the most common directory name or keyword as the feature name
   - Example: Two commits touching `Logging/` → "Feature: Logging improvements"
   - Example: Three commits about "session" → "Feature: Session management"
4. Single unrelated commits become their own group

#### PR Group Format

Three types of PR groups:

```
PR 1: [Ivy-Framework] #42 Add RadialBarChart widget
  Repo: D:\Repos\_Ivy\Ivy-Framework
  Base: origin/main
  Branch: main
  Issue: https://github.com/Ivy-Interactive/Ivy-Framework/issues/42
  Confidence: Explicit reference
  Commits:
    - abc1234 Add RadialBarChart backend widget class (Closes #42)
    - def5678 Add RadialBarChart frontend component (#42)

PR 2: [Ivy-Agent] #15 Session timeout handling
  Repo: D:\Repos\_Ivy\Ivy-Agent
  Base: origin/main
  Branch: main
  Issue: https://github.com/Ivy-Interactive/Ivy-Agent/issues/15
  Confidence: Smart match (score: 85)
  Commits:
    - jkl3456 Refactor session management
    - mno7890 Add timeout configuration

Suggested Match (requires approval):
  Commit: xyz1234 Fix badge border styling (Ivy-Framework)
  → Issue #67 "Badge component border issues" (score: 65)
  Accept match? (y/n)

PR 3: [Ivy-Mcp] Feature: Logging improvements
  Repo: D:\Repos\_Ivy\Ivy-Mcp
  Base: origin/main
  Branch: main
  Commits:
    - pqr1234 Add structured logging
    - stu5678 Improve error messages
```

### 4. Present Plan to User

**Enter plan mode** (using the EnterPlanMode tool) and present the PR groups as a plan.

First, present any **Suggested Matches** (score 40-69) for user approval:
```
Suggested Matches (approve or reject each):

  1. Commit: xyz1234 Fix badge border styling (Ivy-Framework)
     → Issue #67 "Badge component border issues" (score: 65)
     Accept? (y/n)

  2. Commit: abc9876 Update session config (Ivy-Agent)
     → Issue #15 "Session timeout handling" (score: 52)
     Accept? (y/n)
```

After processing suggested matches, present the full PR plan. Each group should show:
- Proposed PR title
- Full repo path on disk
- Current branch name (to restore after cherry-pick)
- List of commits (short hash + subject)
- Estimated base branch (usually origin/main or origin/master)
- Linked issue (shown as `Issue:` line) — for issue-based PRs only
- Confidence level (Explicit reference, Smart match with score, or Feature-based)

Example plan format:
```
PR 1: [Ivy-Framework] #42 Add RadialBarChart widget
  Repo: D:\Repos\_Ivy\Ivy-Framework
  Base: origin/main
  Branch: main
  Issue: https://github.com/Ivy-Interactive/Ivy-Framework/issues/42
  Confidence: Explicit reference
  Commits:
    - abc1234 Add RadialBarChart backend widget class (Closes #42)
    - def5678 Add RadialBarChart frontend component (#42)

PR 2: [Ivy-Agent] #15 Session timeout handling
  Repo: D:\Repos\_Ivy\Ivy-Agent
  Base: origin/main
  Branch: main
  Issue: https://github.com/Ivy-Interactive/Ivy-Agent/issues/15
  Confidence: Smart match (score: 85)
  Commits:
    - jkl3456 Refactor session management
    - mno7890 Add timeout configuration

PR 3: [Ivy-Mcp] Feature: Logging improvements
  Repo: D:\Repos\_Ivy\Ivy-Mcp
  Base: origin/main
  Branch: main
  Confidence: Feature-based grouping
  Commits:
    - pqr1234 Add structured logging
    - stu5678 Improve error messages
```

Issue-based PRs (explicit + smart match) include the `Issue:` and `Confidence:` lines. Feature-based PRs omit the `Issue:` line but include `Confidence: Feature-based grouping`.

After all PR groups, append the following **Execution Instructions** section to the plan:

```
## Execution Instructions

For each PR group above, execute these steps:

1. `cd <Repo>`
2. `git branch pr/<first-commit-short-hash>-<sanitized-title> <Base>`
3. `git checkout pr/<first-commit-short-hash>-<sanitized-title>`
4. `git cherry-pick <commit1> <commit2> ...` (all commits listed in the group, in order)
5. `git push -u origin pr/<first-commit-short-hash>-<sanitized-title>`
6. `gh pr create --head pr/<first-commit-short-hash>-<sanitized-title> --base main --title "<PR title>" --body "<Summary from commits, with Closes #N for issue-based PRs>"`
7. `git checkout <Branch>` (restore original branch)
8. Open the PR URL in the browser
9. Drop the cherry-picked commits from `<Branch>`: `git checkout <Branch>` then `git rebase --onto <commit-before-first-cherry-picked> <last-cherry-picked> <Branch>` (or use `git rebase -i` equivalent). This always happens — the commits are "lifted out" of the original branch into the PR branch.
10. Verify you are back on the original `<Branch>`

Notes:
- Sanitize title for branch name: lowercase, replace spaces with hyphens, remove special chars, truncate to ~50 chars
- If cherry-pick fails, abort (`git cherry-pick --abort`), clean up the branch, and skip this PR
- For issue-based PRs (explicit reference or smart match), append `Closes #N` to the PR body; omit for feature-based PRs
```

> **Important**: The plan must be fully self-contained because exiting plan mode clears context. The PR groups plus the Execution Instructions section must include everything needed to create the PRs from scratch — the agent executing these steps will have NO other context beyond this plan text.

The user can review, modify, or remove groups before approving. Once the user approves the plan, exit plan mode and only execute on the PR groups that remain in the approved plan.

### 5. Execute Approved Plan

Execute the PR groups from the approved plan using the Execution Instructions at the bottom of the plan. The plan is self-contained — do not rely on any context from prior steps.

For each PR group that remains in the approved plan:

#### A. Get PR Details from User
- **PR Title** (suggest from commits, allow editing)
- **PR Body** (generate summary from commits, allow editing)
  - For issue-based PRs (explicit reference or smart match), append a single `Closes #N` line to the body
  - For cross-repo issues, use full URL syntax: `Closes Ivy-Interactive/Ivy-Framework#42`
  - For feature-based PRs, don't include any Closes references
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
2. Build the PR body with summary and issue reference:
   ```markdown
   ## Summary
   <generated summary from commits>

   Closes #42
   ```
   For feature-based PRs, omit the `Closes` line entirely.
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
- `-AutoApprove`: Skip plan approval prompt and create all PRs automatically. For smart matching: auto-approves high-confidence matches (score ≥ 70) but still prompts for suggested matches (score 40-69)
- `-AutoApproveAll`: Like `-AutoApprove` but also auto-accepts suggested matches (score 40-69) without prompting
- `-AutoAssign [user]`: Automatically assign all PRs to the specified user
- `-SkipUncommitted`: Skip the uncommitted changes check and only work with committed changes
- `-Repo [name]`: Only process the specified repository (e.g., `-Repo Ivy-Framework`)

## Error Handling

- If no unpushed commits found, inform user and exit gracefully
- If git commands fail, show error and continue with other repos
- If cherry-pick conflicts occur, abort and skip that PR
- If gh CLI not available, error and exit (gh is required)
- If repo not found, skip it with a warning
- If `gh issue view` fails for a referenced issue, warn but continue with PR creation

## Tools

Store reusable PowerShell functions in Tools/ such as:
- `Get-UnpushedCommits.ps1` - Get unpushed commits for a repo
- `New-PrBranch.ps1` - Create and cherry-pick commits to new branch
- `Group-CommitsByTopic.ps1` - Smart grouping logic
- `Match-CommitToIssue.ps1` - Score a commit against an issue (keyword, file path, label, and title similarity matching). Returns a score 0-100 and breakdown by category. Reusable outside MakePrs.

## Notes

- Always validate that gh CLI is installed: `Get-Command gh -ErrorAction SilentlyContinue`
- Use `git config --global diff.tool vscode` for consistent diff viewing if needed
- Respect git hooks and signing - never use --no-verify or --no-gpg-sign
- If a PR creation fails, continue with remaining PRs
- Cherry-picking preserves original commit authors and messages
