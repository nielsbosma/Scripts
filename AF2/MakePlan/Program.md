# MakePlan

> **⚠️ READ-ONLY MODE: You must NEVER create, edit, or delete any files outside of `D:\Repos\_Ivy\.plans\`. You may only READ source files. The ONLY files you are allowed to write are plan files in `.plans\` and the `.plans\.counter` file.**

Create an implementation plan for a task described in args in the Ivy ecosystem.

## Context

Plans are stored in `D:\Repos\_Ivy\.plans\`. Each plan gets a sequential numeric ID from the counter file `.counter` in that directory.

Read about the important paths and files in ../.shared/Paths.md

## Execution Steps

### 1. Parse Args

Args contains the user's task description. If it references related plans with `[number]` syntax (e.g. `[205]`), find and read those plan files from `D:\Repos\_Ivy\.plans\` for context.

**Extract Criticality Level**: Look for a criticality or priority level indicator in Args (e.g., "How critical is this fix:" followed by CRITICAL, NICETOHAVE, or NITPICK). If not specified, default to NICETOHAVE.

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
`<ID>-<Queue>-<LEVEL>-<Title>.md`

Queue: `IvyAgent`, `IvyConsole`, `IvyFramework`, `General`, `Scripts`, `VsExtension`, `TestManager`, `IvyMcp`, ...
Every project is executed sequentially in a queue of it's own to avoid build errors and conflicting changes.

LEVEL (priority/criticality):
- **CRITICAL** — Must be fixed immediately, blocks work or causes severe issues
- **NICETOHAVE** — Improves functionality but not urgent
- **NITPICK** — Minor polish, cosmetic fixes, or low-priority refinements

Example: `670-IvyFramework-CRITICAL-FaqCardVsBoxComposition.md`  

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

### New Widget Checklist

When a plan involves **creating a new widget** (queue = `IvyFramework`), the plan MUST include steps for ALL of the following:

1. **Backend widget class** — `src/Ivy/Widgets/<WidgetName>.cs` with proper `[Prop]`/`[Event]` attributes, `[JsonIgnore]` on non-serializable delegates, and computed `Has*` booleans for the frontend
2. **Frontend React component** — `src/frontend/src/widgets/<widgetName>/<WidgetName>Widget.tsx` following established patterns (see existing widgets like `StepperWidget.tsx`, `BadgeWidget.tsx` for reference)
3. **Index export** — `src/frontend/src/widgets/<widgetName>/index.ts`
4. **Widget map registration** — Add import and `'Ivy.<WidgetName>': <WidgetName>Widget` entry in `src/frontend/src/widgets/widgetMap.ts`
5. **Sample app** — `src/Ivy.Samples.Shared/Apps/Widgets/<WidgetName>App.cs` demonstrating key features (basic usage, configuration options, event handling)
6. **Documentation page** — `src/Ivy.Docs.Shared/Docs/02_Widgets/<category>/<WidgetName>.md` with ingress, usage examples (`demo-below`/`demo-tabs`), configuration options, and `WidgetDocs` footer

If the backend widget already exists (e.g., adding a missing frontend), the plan should still verify/reference all six elements and note which already exist vs. which need to be created.

### IvyFramework Verification

When a plan targets **IvyFramework** (queue = `IvyFramework`) **and the change affects visual/UI behavior** (e.g., fixing a widget bug, changing layout, adding a new component), add verification instructions to the **Tests** section as the final test step. This ensures verification is treated as a mandatory step rather than optional post-work.

**Do NOT add verification for non-visual changes** such as documentation updates, FAQ entries, analyser error messages, refactoring rules, or code-only fixes that don't affect rendered output.

Add this as the final step in the Tests section:

```markdown
## Tests

1. Build the Ivy Framework project to ensure compilation succeeds
2. Run manual tests as needed (e.g., navigate to sample app, verify behavior)
3. Verify documentation renders correctly (if applicable)

### Visual Verification (REQUIRED)

**You MUST run IvyFeatureTester.ps1 to verify this change visually before committing.**

Execute the following command and wait for completion:

\```powershell
cd D:\Repos\_Ivy
D:\Repos\_Personal\Scripts\AF2\IvyFeatureTester.ps1 "Commit <COMMIT_ID>: <description of what to test>. Test with <specific test scenario>."
\```

Replace `<COMMIT_ID>` with the actual commit hash. The script will:
- Create a worktree at D:\Temp\IvyFeatureTester
- Set up the testing environment
- Launch the Ivy samples app for manual verification

Wait for the visual verification to complete and confirm the test passed before proceeding to commit.
```

The prompt should describe the expected behavior and suggest a concrete test scenario appropriate for the change.

### If Tests Find Issues

If the IvyFeatureTester discovers problems during verification, it should **automatically create a new implementation plan** to fix the discovered issues:

1. Create a new plan file in D:\Repos\_Ivy\.plans\ with a descriptive name (e.g., 417-IvyFramework-CRITICAL-RadialBarChart-FollowUpFix.md)
2. The plan should include:
   - Clear problem description from test results
   - Root cause analysis if identifiable
   - Proposed solution steps
   - Test verification steps
   - Reference back to this original plan (417)
3. Queue the new plan for execution by adding it to the appropriate queue file

This ensures any issues discovered during testing have a tracked resolution path.

### Rules

- **!CRITICAL: Every MakePlan execution MUST produce at least one plan file. Even if the task is an analysis, review, or investigation — always create a plan with actionable steps. Never just analyze and report back without a plan.**
- The plan must include all paths and information for an LLM coding agent to execute end-to-end without human intervention
- Keep the plan short and concise
- **!IMPORTANT: ONE issue per plan file — if multiple issues, create multiple plan files with separate IDs**
- **!CRITICAL: This agent is READ-ONLY for all source code. You must NEVER use Edit, Write, or Bash to create, modify, or delete any file outside `D:\Repos\_Ivy\.plans\`. The ONLY writable paths are:**
  - `D:\Repos\_Ivy\.plans\*.md` (plan files)
  - `D:\Repos\_Ivy\.plans\.counter`
  - Your own Memory/ and Tools/ directories
  - Your log file
