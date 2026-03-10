# IvyAgentDebug

Investigate an Ivy Agent session and generate plans for any findings.

## Context

Args contains the session/trace ID and any additional investigation prompt from the user.

Read about the important paths and files in ../.shared/Paths.md

Read `/Memory/Langfuse.md` for detailed Langfuse analysis steps, JSON path cheat sheets, and debugging recipes.

Plans are stored in `D:\Repos\_Ivy\.plans\`. Each plan gets a sequential numeric ID from the counter file `.counter` in that directory.

## Execution Steps

### 1. Get Debug Folder

```
powershell -Command '[Environment]::GetEnvironmentVariable("IVY_AGENT_DEBUG_FOLDER", "User")'
```
If empty, try Machine scope.

### 2. Fetch Session Data

- Check if a `langfuse` subfolder exists in the session folder
- If not, fetch it: `ivy-agent langfuse session get <session-id>`
- Run the compact timeline: `ivy-agent langfuse session timeline --session-id <session-id> -c`
- If multiple traces exist, present them and focus on the most relevant one

IMPORTANT: Always use the `ivy-agent` CLI tool (in PATH). Do NOT use `dotnet run`.

### 3. Investigate: Hallucinations

- Find `BuildProjectResultMessage` observations with build errors
- Look at the question sequences and code writes leading up to each failed build
- Identify cases where the agent used a non-existent or incorrect **Ivy Framework** API
- Ignore non-hallucination causes: missing assemblies, NuGet packages, target framework issues, transitive dependencies
- Check if a refactoring rule in `IvyCSharpRefactoringService.cs` could prevent the hallucination
- Document findings as plans (not direct edits to hallucinations.md)

### 4. Investigate: Questions

- Find `IvyQuestion` tool calls where the agent didn't get a satisfactory answer
- Check if the Q&A should be added to `D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared\Docs\05_Other\Faq.md`
- Check if the question is already in the FAQ — if so, assess if the existing answer needs improvement
- Document findings as plans

### 5. Investigate: Workflows

If the session involves workflows (`WorkflowStartMessage` events):
- Read the workflow source code and prompt templates
- Understand the intended flow vs what actually happened
- Look for transition issues, incorrect question sequences, or tool feedback errors

### 6. Investigate: Reflect

- Analyze the debugging session for areas of improvement
- Consider: logging improvements, better tooling, clearer instructions
- Document findings as plans

### 7. Generate Plans

For each finding, create a plan file in `D:\Repos\_Ivy\.plans\`.

- Read the counter from `.counter` (default 200 if missing), allocate IDs, increment
- Format: `<ID>-<RepositoryName>-Feature-<Title>.md`
- Repository names: `IvyAgent`, `IvyConsole`, `IvyFramework`, `General`
- Before creating a plan, search existing plans to avoid duplicates — update existing plans if they partially cover the finding

Plan format:

```markdown
---
source: <IVY_AGENT_DEBUG_FOLDER>\<session-id>\
---
# [Title]

## Problem

## Solution

## Clean up

1. Commit
```

### Rules

- **Everything must be expressed as plans** — hallucination docs, FAQ edits, issue creation, improvements
- ONE issue per plan file
- Plans must include all paths and information for an LLM coding agent to execute end-to-end
- Keep plans short and concise
- Do NOT modify any source code directly — only read files and create plan files
