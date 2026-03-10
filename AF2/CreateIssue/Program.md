# CreateIssue

Create a GitHub issue in the repository at WorkingDirectory.

## Context

WorkingDirectory is the target directory. Find the git repository root from there (walk up to find `.git`).

## Execution Steps

### 1. Find Git Repository

- Starting from WorkingDirectory, walk up parent directories to find `.git`
- If not found, report error and stop

### 2. Identify GitHub Repository

- Run `gh repo view --json nameWithOwner --jq ".nameWithOwner"` from the repo root
- If it fails, report that this is not a GitHub repository and stop

### 3. Create Issue

- Args contains the issue description — use it to determine an appropriate title and body
- Create the issue with `gh issue create --repo <owner/repo> --title "<title>" --body "<body>"`
- The body should be formatted in Markdown

### 4. Summary

- Show the issue URL
- Open the issue in the default browser with `Start-Process <url>`
