# RunCs - Code Health Plan Generator

> **READ-ONLY MODE: You must NEVER create, edit, or delete any files outside of `D:\Repos\_Ivy\.plans\`. You may only READ source files. The ONLY files you are allowed to write are plan files in `.plans\` and the `.plans\.counter` file.**

Scan the Ivy codebase using the CodeScene CLI (`cs`) to find code health issues, then create implementation plans for the worst findings.

Read about the important paths and files in ../.shared/Paths.md

## Prerequisites

Verify `cs` CLI is available and authenticated:
```bash
cs version
```
If not found, inform the user and exit.

The `cs` CLI requires a Personal Access Token. Verify it's set:
```bash
echo $CS_ACCESS_TOKEN
```
If not set, inform the user:
- Generate a PAT at https://codescene.io/users/me/pat
- Set `$env:CS_ACCESS_TOKEN = '<your-PAT>'` before running this script
- Then exit.

## Execution Steps

### 1. Parse Args

Args may contain:
- Specific repo to scan (e.g., "Ivy-Framework", "Ivy-Agent", "Ivy", "Ivy-Mcp")
- Specific file or directory to scan
- If no args or "(No Args)", scan all repos

### 2. Scan for Code Health Issues

Run `cs review` with JSON output across the target C# source files. Scan these repos:

| Repo Path | Queue |
|---|---|
| `D:\Repos\_Ivy\Ivy-Framework\src\` | IvyFramework |
| `D:\Repos\_Ivy\Ivy-Agent\` | IvyAgent |
| `D:\Repos\_Ivy\Ivy\` | IvyConsole |
| `D:\Repos\_Ivy\Ivy-Mcp\` | IvyMcp |

For each repo, find `.cs` files excluding `obj/`, `bin/`, and test projects (directories containing `.Test`, `.Tests`, or `.Eval` in their name).

Run on each file:
```bash
cs review <file> --output-format json
```

The JSON output includes a `score` (1-10, where 10 is healthiest) and a list of code health issues with categories and details.

Also run `cs check` for linter-style output to include in plans:
```bash
cs check <file>
```

Collect all results and parse to identify:
- File path
- Code health score
- Issue types and descriptions
- Severity (derived from score: 1-3 = critical, 4-6 = degraded, 7-9 = minor, 10 = healthy)

### 3. Rank and Select Top Issues

- Sort files by score ascending (worst health first)
- Skip files with score >= 9 (healthy enough)
- Select the top 10 worst-scoring files
- **Max 10 plans per session**

### 4. Check for Duplicate Plans

Before creating plans, read existing plan files in `D:\Repos\_Ivy\.plans\` and check if any already reference the same source file path. Skip duplicates.

### 5. Create Plans

For each selected file, allocate a plan ID from `.counter` and create a plan file following the MakePlan convention.

#### Plan ID Allocation

- Read the counter from `D:\Repos\_Ivy\.plans\.counter` (default 200 if missing)
- Reserve the next ID and increment the counter
- Format as 3-digit zero-padded (e.g. `205`)

#### Plan Naming

`<ID>-<Queue>-NiceToHave-CodeHealth-<ShortTitle>.md`

Determine the queue from the repo:
- `Ivy-Framework\src\` -> `IvyFramework`
- `Ivy-Agent\` -> `IvyAgent`
- `Ivy\` -> `IvyConsole`
- `Ivy-Mcp\` -> `IvyMcp`

#### Plan Format

```markdown
---
source: <path-to-affected-file>
session: <SessionId from header>
workflow:
references:
---
# Fix Code Health: <FileName> (<Score>/10)

## Problem

CodeScene `cs check` identified the following code health issues:

<paste cs check output for this file>

File: `<path>`
Score: <score>/10
Issues: <list of issue categories>

## Solution

<Describe concrete steps to fix the code health issues. Read the affected file to understand the context and provide specific refactoring instructions.>

## Tests

1. Run `cs review <file> --output-format json` to verify the score has improved
2. Run existing tests for the affected project:
   ```bash
   cd <project-path>
   dotnet test
   ```
3. Verify no regressions in related test projects

Relevant test projects:
- `IvyFramework` -> `Ivy.Test`, `Ivy.Tests`, `Ivy.Analyser.Test`, `Ivy.Filters.Tests` (all in `D:\Repos\_Ivy\Ivy-Framework\src\`)
- `IvyAgent` -> `Ivy.Agent.Test`, `Ivy.Agent.Shared.Test`, `Ivy.Llm.Test` (all in `D:\Repos\_Ivy\Ivy-Agent\`)
- `IvyConsole` -> `Ivy.Console.Test`, `Ivy.Internals.Test` (in `D:\Repos\_Ivy\Ivy\`)
- `IvyMcp` -> test projects in `D:\Repos\_Ivy\Ivy-Mcp\`

## Finish

Commit!
```

### Rules

- **Max 10 plans per session**
- **ONE file per plan** (a file may have multiple issues — group them in one plan)
- All plans get NiceToHave level unless the score is 1-3 (use Critical for those)
- Read the affected source file before writing the plan to provide specific fix instructions
- Keep plans concise and actionable
- **READ-ONLY: Only write to `.plans\` directory**
