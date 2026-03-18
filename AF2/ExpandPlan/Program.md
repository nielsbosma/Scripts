# ExpandPlan

Transform investigation-heavy plans into concrete, decision-ready implementation plans.

## Context

Plans are stored in `D:\Repos\_Ivy\.plans\`. The input file has been moved to `D:\Repos\_Ivy\.plans\expanding\` before this program runs. Args contains the path to the file in `expanding/`. Output files must be written to `D:\Repos\_Ivy\.plans\` (the parent directory, not `expanding/`).

Read about the important paths and files in ../.shared/Paths.md

## Goal

Transform plans containing research questions, unknowns, or investigative steps into **concrete, actionable plans** where:
- All research is completed
- All unknowns are resolved
- All design decisions are identified with concrete options
- Developers can implement immediately without further investigation

## Execution Steps

### 1. Parse Args

Args contains the path to a plan file. Resolve it to an absolute path.

### 2. Back Up

- Copy the current plan to `D:\Repos\_Ivy\.plans\history\` (create if needed)

### 3. Deep Analysis of the Plan

Read the plan file and identify:

1. **Investigation sections** — phrases like:
   - "Investigate...", "Check if...", "Verify whether...", "Research...", "Explore..."
   - "TODO: decide", "Need to determine", "Figure out"

2. **Assumptions** — statements that may or may not be true:
   - "Assuming X works...", "If Y exists...", "Should be similar to..."

3. **Ambiguities** — vague or incomplete instructions:
   - "Fix the issue", "Update as needed", "Make it work"
   - Missing file paths, class names, or method signatures

4. **Design decisions** — places where multiple approaches are possible:
   - "Either X or Y", "Consider doing...", "Possibly..."

### 4. Exhaustive Research and Resolution

For each identified issue, perform comprehensive research:

#### A. Code Investigation
1. **Read all relevant source files** (not just mentioned ones)
   - Current implementation of related features
   - Existing patterns and conventions in the codebase
   - Similar components that solve related problems

2. **Trace dependencies**
   - What components depend on this?
   - What breaking changes might occur?
   - What tests exist that might be affected?

3. **Verify assumptions**
   - Check if assumed files/classes/methods actually exist
   - Confirm behavior matches what the plan assumes
   - Identify incorrect assumptions and correct them

#### B. Architecture Context
1. **Identify established patterns**
   - How does the codebase handle similar scenarios?
   - What architectural decisions guide this area?
   - Are there framework conventions to follow?

2. **Check documentation**
   - Read relevant docs in `Ivy.Docs.Shared/Docs/`
   - Review `AGENTS.md` for agent-specific patterns
   - Check refactor prompts in `.releases/Refactors/`

#### C. Decision Resolution
When multiple approaches are possible:

1. **Research each option thoroughly**
   - How is each done elsewhere in the codebase?
   - What are the technical pros/cons?
   - What are the maintenance implications?

2. **Present concrete alternatives** with:
   - Specific implementation approach for each
   - Pros and cons based on research findings
   - Recommendation based on codebase patterns

**Example transformation:**

**Before:**
```
1. Investigate the dialog rendering lifecycle:
   - Check dialog component
   - Check form builder
   - Test with minimal repro
```

**After:**
```
1. Fix dialog content initialization race condition in Dialog.razor.cs:147

   **Root Cause:** Dialog animation starts before child components (FormBuilder) complete their UseState initialization, causing form fields to render with stale data.

   **Implementation:**
   - In `src/Ivy/Components/Dialog.razor.cs:147`, wrap StateHasChanged() with Task.Yield() before animation
   - In `src/Ivy/Components/FormBuilder.razor.cs:89`, add SynchronousStateInitialization flag for dialog context
   - Follow pattern from `src/Ivy/Components/Drawer.razor.cs:234` which solved identical issue

   **Files to modify:**
   - `src/Ivy/Components/Dialog.razor.cs` (line 147, 156)
   - `src/Ivy/Components/FormBuilder.razor.cs` (line 89, add property at line 23)

   **Tests:**
   - Add unit test in `tests/Ivy.Tests/Components/DialogTests.cs` following pattern from DrawerTests.cs:156
   - Test case: Dialog with FormBuilder containing 5+ fields with default values
```

### 5. Create Concrete Implementation Plan

The expanded plan must be **immediately actionable** with zero remaining research needed. It should contain:

#### Required Elements:

1. **Exact file paths with line numbers**
   - Not: "Update the Dialog component"
   - Yes: "In `src/Ivy/Components/Dialog.razor.cs:147`, modify the StateHasChanged() call"

2. **Specific code changes**
   - Not: "Fix the initialization"
   - Yes: "Wrap StateHasChanged() with `await Task.Yield()` before animation start"

3. **Referenced patterns from codebase**
   - "Follow pattern from `src/Ivy/Components/Drawer.razor.cs:234`"
   - "Use same approach as TableWidget for state management"

4. **Root cause analysis** (when fixing bugs)
   - What specifically causes the issue
   - Why it happens (timing, state, lifecycle, etc.)
   - Evidence from research

5. **Decision points** (when multiple valid approaches exist)
   ```markdown
   ## DECISION REQUIRED: State Management Approach

   ### Option A: Local Component State (RECOMMENDED)
   - Modify `BadgeWidget.tsx` to use useState hook
   - Pros: Simple, follows pattern in ButtonWidget, StepperWidget
   - Cons: Requires re-render on count change
   - Files: 1 file, ~10 lines

   ### Option B: Global Context State
   - Create BadgeContext.tsx, modify provider in App.tsx
   - Pros: Shares state across badge instances
   - Cons: Added complexity, no other widgets use this pattern
   - Files: 2 new files, 3 modified files, ~50 lines

   **Recommendation:** Option A - aligns with existing widget patterns and simpler maintenance
   ```

6. **Impact analysis**
   - What other components might be affected?
   - Are there breaking changes?
   - What tests need updating?

7. **Verification steps**
   - Not: "Test the feature"
   - Yes: "Run the BadgeApp sample, verify count increments on click, check console for errors"

#### Structure Requirements:

- Keep original structure: Problem, Solution, Tests, Finish
- Preserve YAML frontmatter exactly as-is
- Replace ALL investigative language with concrete actions
- Include all context and problem description
- Add "Research Findings" section if significant discoveries were made

#### Quality Checks:

Before saving, verify:
- [ ] No phrases like "investigate", "check if", "research", "explore", "TODO", "decide"
- [ ] No vague terms like "update as needed", "fix the issue", "make it work"
- [ ] All file paths are absolute and include line numbers where applicable
- [ ] All assumptions have been verified or corrected
- [ ] All design decisions either resolved or presented with concrete options
- [ ] A developer can implement this without opening any file for research

### 6. Handle Special Cases

#### If Problem Doesn't Exist:
```markdown
## Research Findings

Investigation revealed this issue was already resolved in commit abc1234.
The Dialog component now handles content initialization correctly.

## Recommendation

Close this plan without implementation. The original issue no longer exists.
```

#### If Problem Requires Architecture Change:
Create decision-focused plan:
```markdown
## Research Findings

Current architecture uses X pattern. Implementing this feature requires either:
1. Extend X pattern (moderate complexity)
2. Refactor to Y pattern (high complexity, affects 12 components)

## DECISION REQUIRED: Architecture Approach

[Detailed options with research-backed pros/cons]
```

#### If Multiple Issues Found:
Create separate plans for each issue:
- Create `<ID>-<Queue>-<LEVEL>-<OriginalTitle>-Issue1.md`
- Create `<ID>-<Queue>-<LEVEL>-<OriginalTitle>-Issue2.md`
- Each plan should be independently actionable

### 7. Save Expanded Plan

- Version the filename: append `-expanded`, or if already versioned append `-expanded` before version (`-v2` → `-v2-expanded`)
- Write the expanded plan to `D:\Repos\_Ivy\.plans\` with the new filename
- Delete the original file from `expanding/` (the history copy serves as backup)
- If multiple plans were created, save all to `.plans\` and delete original

### Rules

- **!CRITICAL: Do NOT add `>>` comments** — this is not an update workflow
- **!CRITICAL: The expanded plan must be immediately actionable** — no further investigation required
- **Do NOT modify any source code** — only read files to research and transform the plan
- **Do NOT create new issues** — only transform the existing plan(s)
- If research reveals fundamentally different problems, create multiple concrete plans
- Every uncertainty MUST be resolved — no "TODO", no "check if", no open questions
- When in doubt about a design decision, provide concrete options with recommendation
- Always verify file paths and line numbers actually exist
- Preserve all verification steps and test requirements
