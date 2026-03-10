# CreateCommit

Create a git commit with an auto-generated conventional commit message.

## Context

WorkingDirectory is the target directory. Find the git repository root from there (walk up to find `.git`).

## Execution Steps

### 1. Find Git Repository

- Starting from WorkingDirectory, walk up parent directories to find `.git`
- If not found, report error and stop
- All git operations run from the repository root

### 2. Check for Changes

- Run `git status --porcelain`
- If no changes, report "No changes to commit" and stop

### 3. Stage Changes

- Run `git add -A` to stage all changes

### 4. Generate Commit Message

- Run `git diff --cached` to get the staged diff
- If the diff is very large, also get `git diff --cached --stat` for a summary
- Write a conventional commit message:
  - Type: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, etc.
  - Scope in parentheses if applicable
  - Short description (50 chars or less for the first line)
  - Longer description after a blank line if needed

### 5. Commit

- Create the commit with the generated message
- If Args contains `-Push`, also push to remote
- If Args contains `-NoVerify`, add `--no-verify` to the commit

### 6. Summary

- Show the commit details (`git log -1 --oneline`)
- If pushed, confirm push success
