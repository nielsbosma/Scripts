# ExpandPlan

Transform investigation-heavy plans into concrete implementation plans.

## Context

Plans are stored in `D:\Repos\_Ivy\.plans\`. The input file has been moved to `D:\Repos\_Ivy\.plans\expanding\` before this program runs. Args contains the path to the file in `expanding/`. Output files must be written to `D:\Repos\_Ivy\.plans\` (the parent directory, not `expanding/`).

Read about the important paths and files in ../.shared/Paths.md

## Execution Steps

### 1. Parse Args

Args contains the path to a plan file. Resolve it to an absolute path.

### 2. Back Up

- Copy the current plan to `D:\Repos\_Ivy\.plans\history\` (create if needed)

### 3. Read and Analyze the Plan

- Read the plan file
- Identify all sections that mention "investigation", "investigate", "research", or contain open-ended exploratory steps
- These sections typically have phrases like:
  - "Investigate..."
  - "Check if..."
  - "Verify whether..."
  - "Research..."
  - "Explore..."

### 4. Research and Resolve Investigations

For each investigation section:

1. **Read relevant source files** to understand the current implementation
2. **Answer the investigation questions** by examining:
   - Existing code patterns
   - Documentation
   - Related components
   - Framework conventions
3. **Transform into concrete steps** — replace "Investigate X" with specific implementation tasks based on research findings

Example transformation:

**Before:**
```
1. Investigate the dialog rendering lifecycle:
   - Check dialog component
   - Check form builder
   - Test with minimal repro
```

**After:**
```
1. Fix dialog content initialization race condition:
   - In `Dialog.cs`, add immediate content rendering before animation
   - In `FormBuilder.cs`, ensure UseState hooks execute synchronously in dialog context
   - Add unit test for dialog-with-form pattern
```

### 5. Create Concrete Implementation Plan

The expanded plan should:

- Replace all investigative/exploratory language with specific actions
- Include exact file paths for changes
- Specify concrete code modifications or additions
- Provide step-by-step implementation sequence
- Maintain all original context and problem description
- Keep the same structure (Problem, Solution, Tests, Finish)
- Preserve YAML frontmatter exactly as-is

### 6. Save Expanded Plan

- Version the filename: append `-expanded`, or if already versioned append `-expanded` before version (`-v2` → `-v2-expanded`)
- Write the expanded plan to `D:\Repos\_Ivy\.plans\` with the new filename
- Delete the original file from `expanding/` (the history copy serves as backup)

### Rules

- **Do NOT add `>>` comments** — this is not an update workflow
- The expanded plan must be **immediately actionable** without further investigation
- If research reveals the problem is already solved or doesn't exist, note that clearly in the expanded plan
- Preserve all verification steps and test requirements
- **When referencing local files in expanded plans, use markdown links: `[FileName.cs](file:///path/to/FileName.cs)`**
- Keep the plan self-contained with all paths and information for an LLM coding agent
- Do NOT modify any source code — only read files and transform the plan
