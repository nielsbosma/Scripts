# CreatePullRequest

Create a GitHub pull request from unpushed commits with an AI-generated branch name, title, and description.

## Context

WorkingDirectory is the target directory. Find the git repository root from there (walk up to find `.git`).

## Execution Steps

### 1. Find Git Repository

- Starting from WorkingDirectory, walk up parent directories to find `.git`
- If not found, report error and stop

### 2. Validate State

- Verify a remote is configured (`git remote -v`)
- Check for uncommitted changes (`git status --porcelain`) — if any exist, report error and stop
- Check for unpushed commits (`git log origin/<branch>..HEAD --oneline`) — if none, report "Nothing to create a PR for" and stop

### 3. Create Branch

- Get the unpushed commit messages and diff
- Generate a concise branch name: lowercase, hyphens, type prefix (`feature/`, `fix/`, `chore/`, etc.), under 50 chars
- Check the branch doesn't already exist
- Create and switch to the new branch (`git checkout -b <name>`)

### 4. Push Branch

- Push to remote with tracking (`git push -u origin <name>`)
- If push fails, switch back to original branch and clean up

### 5. Create Pull Request

- Generate a PR title: concise, under 72 chars, descriptive of the main change
- Generate a PR body in Markdown with: overview, changes summary, code examples for significant additions, notes
- Create the PR with `gh pr create --title "<title>" --body "<body>" --base <original-branch>`

### 6. Post-Creation

- If Args contains `-Reviewer <name>`, add reviewer with `gh pr edit <number> --add-reviewer <name>`
- If Args contains `-Approve`, approve with `gh pr review <number> --approve`
- If Args contains `-Open`, open the PR URL in the browser with `Start-Process <url>`
- Switch back to the original branch

### 7. Summary

- Show the PR URL and number
- Confirm branch was pushed and PR is ready for review
