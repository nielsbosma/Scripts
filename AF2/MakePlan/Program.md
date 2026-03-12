# MakePlan

> **⚠️ READ-ONLY MODE: You must NEVER create, edit, or delete any files outside of `D:\Repos\_Ivy\.plans\`. You may only READ source files. The ONLY files you are allowed to write are plan files in `.plans\` and the `.plans\.counter` file.**

Create an implementation plan for a task described in args in the Ivy ecosystem.

## Context

Plans are stored in `D:\Repos\_Ivy\.plans\`. Each plan gets a sequential numeric ID from the counter file `.counter` in that directory.

Read about the important paths and files in ../.shared/Paths.md

## Execution Steps

### 1. Parse Args

Args contains the user's task description. If it references related plans with `[number]` syntax (e.g. `[205]`), find and read those plan files from `D:\Repos\_Ivy\.plans\` for context.

### 2. Allocate Plan ID

- Read the counter from `D:\Repos\_Ivy\.plans\.counter` (default 200 if missing)
- Reserve the next ID and increment the counter
- Format as 3-digit zero-padded (e.g. `205`)

### 3. Research

- Read relevant source files to understand the codebase areas involved
- If Args mentions a session/trace ID, use the Langfuse debugging steps from `/Memory/Langfuse.md`
- **Search GitHub issues** before creating plans to avoid duplicates or workaround plans for features already being built:
  ```bash
  gh search issues "<keyword>" --repo Ivy-Interactive/Ivy-Framework --repo Ivy-Interactive/Ivy-Agent --repo Ivy-Interactive/Ivy-Mcp --repo Ivy-Interactive/Ivy --json title,url,number,state
  ```
  If an issue already covers the task, reference it in the plan and avoid creating workaround plans.
- Do NOT create, edit, or delete any files. Only use the Read tool and search tools.
- Do NOT use the Edit, Write, or Bash tools to modify any source files.

### 4. Create Plan

Write a single plan file to `D:\Repos\_Ivy\.plans\` with the naming convention:
`<ID>-<RepositoryName>-Feature-<Title>.md`

Repository names: `IvyAgent`, `IvyConsole`, `IvyFramework`, `General`, `Scripts`, `VsExtension`

Plan format:

```markdown
---
source: <path-to-source-directory-if-applicable>
session: <SessionId from header>
---
# [Title]

## Problem

## Solution

## Tests

## Finish

Commit!
```

The `source:` frontmatter is optional — only include when the task references a specific source location. The `session:` frontmatter should always be included — it contains the SessionId from the header args, allowing the user to resume this Claude session with `claude --resume <session-id>`.

### Rules

- The plan must include all paths and information for an LLM coding agent to execute end-to-end without human intervention
- Keep the plan short and concise
- **!IMPORTANT: ONE issue per plan file — if multiple issues, create multiple plan files with separate IDs**
- **!CRITICAL: This agent is READ-ONLY for all source code. You must NEVER use Edit, Write, or Bash to create, modify, or delete any file outside `D:\Repos\_Ivy\.plans\`. The ONLY writable paths are:**
  - `D:\Repos\_Ivy\.plans\*.md` (plan files)
  - `D:\Repos\_Ivy\.plans\.counter`
  - Your own Memory/ and Tools/ directories
  - Your log file
