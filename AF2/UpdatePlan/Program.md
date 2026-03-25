# UpdatePlan

Update an existing implementation plan by applying user comments.

## Context

Plans are stored in `D:\Repos\_Ivy\.plans\`. The input file has been moved to `D:\Repos\_Ivy\.plans\updating\` before this program runs. Args contains the path to the file in `updating/`. Output files must be written to `D:\Repos\_Ivy\.plans\` (the parent directory, not `updating/`).

Read about the important paths and files in ../.shared/Paths.md

## Execution Steps

### 1. Parse Args

Args contains the path to a plan file. Resolve it to an absolute path.

### 2. Back Up

- Copy the current plan to `D:\Repos\_Ivy\.plans\history\` (create if needed)

### 3. Read the Plan

- Read the plan file
- Look for lines prefixed with `>>` — these are user comments/instructions
- If no `>>` lines exist, report "No comments found" and stop

### 4. Extract and Answer Questions

- Check each `>>` line to determine if it's a **question** (contains `?`, or starts with question words like "How", "Why", "What", "Is", "Can", "Should", "Does", "Will", "Are", "Where", "When", "Which")
- For each question:
  1. Research the answer by reading relevant source files, documentation, and existing patterns in the codebase
  2. Format as a bullet with the question, followed by a nested `**Answer:**` paragraph
- Collect all answered questions into a `## Questions` section
- Place the `## Questions` section directly after the YAML frontmatter, before `## Problem` (or the first existing heading)
- If a `## Questions` section already exists, merge new questions into it (avoid duplicates)
- If a question truly cannot be answered from available sources, mark it with `**Answer:** Unknown — requires user input.` so it's clear which questions remain open
- Questions are NOT incorporated into the plan body — they stay in `## Questions` as a reference section

### 5. Apply Comments

- Incorporate the intent of each non-question `>>` comment into the plan
- Remove all `>>` lines after applying them (both questions and non-questions)
- Read relevant source files if needed to improve accuracy
- Preserve the plan's markdown structure, frontmatter, and detail level
- The updated plan must be at least as comprehensive as the original

### 6. Save Updated Plan

- Version the filename: append `-v2`, or increment existing version (`-v2` → `-v3`, etc.)
- Write the updated plan to `D:\Repos\_Ivy\.plans\` with the new versioned filename
- Delete the original (unversioned) file since the history copy serves as backup

### IvyFramework Verification

When updating a plan that targets **IvyFramework** (has `IvyFramework` in filename or queue) **and the change affects visual/UI behavior** (e.g., fixing a widget bug, changing layout, adding a new component), ensure the plan includes a `### Verification` section with instructions to run **IvyFeatureTester.ps1** after the commit. If this section is missing, add it.

**Do NOT add verification for non-visual changes** such as documentation updates, FAQ entries, analyser error messages, refactoring rules, or code-only fixes that don't affect rendered output. If an existing plan has verification for a non-visual change, remove it.

```markdown
### Verification

After committing the fix, use **IvyFeatureTester.ps1** to verify the changes visually:

\```powershell
cd D:\Repos\_Ivy
D:\Repos\_Personal\Scripts\AF2\IvyFeatureTester.ps1 "Commit <COMMIT_ID>: <description of what to test>. Test with <specific test scenario>."
\```

Replace `<COMMIT_ID>` with the actual commit hash from the fix commit above.
```

The prompt should describe the expected behavior and suggest a concrete test scenario appropriate for the change.

### Rules

- Preserve YAML frontmatter exactly as-is
- Do NOT summarize, abbreviate, or skip sections
- Do NOT modify any source code — only read files and update the plan file
- **When referencing local files in plans, use markdown links: `[FileName.cs](file:///path/to/FileName.cs)`**
- The plan must remain self-contained with all paths and information for an LLM coding agent
