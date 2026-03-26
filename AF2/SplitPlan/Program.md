# SplitPlan

Split a multi-issue plan file into separate, self-contained plan files.

## Context

Plans are stored in `D:\Repos\_Ivy\.plans\`. Each plan gets a sequential numeric ID from the counter file `.counter` in that directory.

The input file has been moved to `D:\Repos\_Ivy\.plans\updating\` before this program runs. Args contains the path to the file in `updating/`. Output files must be written to `D:\Repos\_Ivy\.plans\` (the parent directory, not `updating/`).

Read about the important paths and files in ../.shared/Paths.md

## Execution Steps

### 1. Parse Args

Args contains the path to a plan file. Resolve it to an absolute path.

### 2. Back Up

- Copy the current plan to `D:\Repos\_Ivy\.plans\history\` (create if needed)

### 3. Allocate Plan IDs

- Read the counter from `D:\Repos\_Ivy\.plans\.counter` (default 200 if missing)
- Reserve one ID per split plan and increment the counter
- Format as 3-digit zero-padded (e.g. `205`)

### 4. Create Split Plans

Write each split plan to `D:\Repos\_Ivy\.plans\` with the naming convention:
`<ID>-<RepositoryName>-<Title>.md`

Repository names: `IvyAgent`, `IvyConsole`, `IvyFramework`, `General`, `Scripts` etc.

Each plan must have the standard format:

```markdown
---
source: <path-to-source-directory-if-applicable>
---
# [Title]

## Problem

## Solution

## Tests

## Finish

Commit!
```

### 6. Clean Up

- Delete the original combined plan file (the history copy serves as backup)

### Rules

- **Must produce at least 2 plan files** — if the content can't be meaningfully split, report this and stop
- Each plan must be fully self-contained with all paths and information for an LLM coding agent
- If the original has YAML frontmatter, copy it to each split plan
- ONE issue per plan file
- Keep each plan short and concise
- **When referencing local files in split plans, use markdown links: `[FileName.cs](file:///path/to/FileName.cs)`**
- **When referencing screenshots or images in plans, use markdown image syntax: `![description](file:///D:/Screenshots/2026-03-26_05-30_3.png)` or clickable link syntax: `[2026-03-26_05-30_3.png](file:///D:/Screenshots/2026-03-26_05-30_3.png)`. Both formats work in VS Code - image syntax renders inline, link syntax is clickable.**
- Do NOT modify any source code — only read files and create plan files
