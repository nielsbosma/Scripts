# IvyAgentReviewBuild

Build an Ivy Agent project, fix all errors and warnings, and document the results.

## Context

Args contains the path to the project folder (e.g. `D:\Temp\IvyAgentRun\ByteForge.UrlCraft`). If no args provided, use the current working directory.

Read about the important paths and files in ../.shared/Paths.md

## Execution Steps

### 1. Clean and Build

Run in the project folder:

```
dotnet clean
dotnet build
```

Capture the full build output.

### 2. Fix Errors and Warnings

If the build has errors or warnings:

- Read the relevant source files
- Fix each error and warning directly in the code
- Re-run `dotnet build` to verify the fix
- Repeat until the build is clean (0 errors, 0 warnings)

Use Ivy Framework docs and samples as reference when needed:
- `D:\Repos\_Ivy\Ivy-Framework\AGENTS.md`
- `D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared\Docs`
- `D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Samples.Shared\`

### 3. Generate Result

Write `.ivy\review-build.md` in the project folder.

If the build was clean from the start:

```markdown
# Build Review: [Project Name]

## Result

✅ Clean build — 0 errors, 0 warnings.
```

If there were issues that were fixed:

```markdown
# Build Review: [Project Name]

## Result

✅ All issues fixed — build is now clean.

## Issues Fixed

### [Error/Warning code]: [Brief description]

**File**: `[path]`
**Type**: Error / Warning
**Message**: [Exact compiler message]

**Fix**: [What was changed and why]

### [Next issue...]

## Summary

| Type | Count |
|------|-------|
| Errors fixed | X |
| Warnings fixed | X |
```

### Rules

- Always start with `dotnet clean` to ensure a fresh build
- Fix ALL warnings, not just errors — the goal is 0 errors and 0 warnings
- Keep fixes minimal — only change what's needed to resolve the issue
- If a fix requires understanding Ivy Framework APIs, consult the docs and samples
- Do not add unnecessary code, refactoring, or improvements beyond what's needed for the fix
