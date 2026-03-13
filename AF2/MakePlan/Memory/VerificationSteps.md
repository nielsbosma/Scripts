# Verification Steps in Plans

## Problem

Visual verification steps placed **after** the "Commit!" instruction in the Finish section are often **skipped** by executing agents. The agent treats "Commit!" as the completion signal and may summarize the verification instructions rather than executing them.

**Example from Plan 500** (2026-03-13):
- Plan included Verification section after Finish/Commit
- Agent created files, built, and committed
- Agent summarized verification step but did not execute IvyFeatureTester.ps1
- Result: No visual testing occurred

## Solution

**Place verification as the final step in the Tests section**, not after the Finish section:

```markdown
## Tests

1. Build to ensure compilation succeeds
2. Run manual tests as needed
3. Verify documentation (if applicable)

### Visual Verification (REQUIRED)

**You MUST run IvyFeatureTester.ps1 to verify this change visually before committing.**

Execute the following command and wait for completion:

\```powershell
cd D:\Repos\_Ivy
D:\Repos\_Personal\Scripts\AF2\IvyFeatureTester.ps1 "Commit <COMMIT_ID>: ..."
\```

Wait for the visual verification to complete and confirm the test passed before proceeding to commit.

## Finish

Commit the changes with message: "..."
```

## Key Points

1. **Placement**: Verification goes in Tests section, NOT after Finish
2. **Language**: Use "MUST" and "REQUIRED" to indicate mandatory steps
3. **Wait instruction**: Explicitly tell agent to wait for completion
4. **Order**: Verification BEFORE commit, not after
5. **Commit placeholder**: `<COMMIT_ID>` gets replaced by agent with actual hash

## When to Add Verification

**Add visual verification for:**
- Widget changes (new widgets, bug fixes, styling)
- Layout changes
- UI behavior changes
- Sample app changes that affect rendering

**Skip verification for:**
- Documentation-only updates
- FAQ entries
- Analyzer error messages
- Refactoring rules
- Code-only changes with no visual impact
- Backend/API changes
