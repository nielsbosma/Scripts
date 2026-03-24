# IvyAgentReviewTests

Generate and run Playwright end-to-end tests for an Ivy Framework .NET web application. Focus on finding runtime errors and ensuring clean logs.

## Context

The user's working directory is provided in the Firmware header as `WorkDir`. This is the Ivy project root (contains a `.csproj` and `Program.cs`). If Args specifies a different project path, use that instead. All project-relative paths are relative to the project root, not your script directory.

Read about the important paths and files in ../.shared/Paths.md

## Execution Steps

### 1. Read Spec

- Read `.ivy\spec.md` in the project folder — this is REQUIRED
- If the spec file doesn't exist, report the error and stop
- Extract all apps, connections, features, and UI requirements from the spec

### 2. Validate Ivy Project

- Confirm the project folder contains a `.csproj` file and `Program.cs`
- If not, report the error and stop
- Identify the project name from the `.csproj` filename

Run the following  to describe what Apps a project contains.

> dotnet run --describe
apps:
- name: App Not Found
  id: $error-not-found
  isVisible: false
- name: Mermaid Editor
  id: mermaid-editor
  isVisible: true
- name: Chrome
  id: $chrome
  isVisible: false
connections: []
secrets: []
services:
- serviceType: Ivy.ServerArgs
  implementationType: Ivy.ServerArgs
  lifetime: Singleton
  description:
- serviceType: Microsoft.Extensions.Configuration.IConfiguration
  implementationType: Microsoft.Extensions.Configuration.ConfigurationRoot
  lifetime: Singleton
  description:
- serviceType: Ivy.IThemeService
  implementationType: Ivy.ThemeService
  lifetime: Singleton
  description:


### 3. Collect Project Source

- Read all `.cs` and `.csproj` files recursively (excluding `bin/`, `obj/`, `.ivy/` directories)
- These provide context for understanding what the app does

### 4. Read Memory

- Read all files in your `/Memory/` folder — this is your accumulated knowledge about Ivy testing patterns
- Apply these learnings when generating tests

### 5. Check Existing Tests

- Look in `.ivy/tests/` within the project for existing `.spec.ts` files
- If they exist, read them — improve or extend, do not duplicate
- Also check for `console.log`, `backend.log` from previous runs — these contain issues to address

### 6. Create Test Directory

- Ensure `.ivy/tests/`, `.ivy/tests/screenshots/`, and `.ivy/tests/videos/` directories exist in the project

### 7. Generate Tests

When writing tests it's very useful to test one Ivy app at at time with out the chrome.
http://localhost:<port>/<app-id>?chrome=false

Write the following files directly to `.ivy/tests/`:

**package.json** — minimal, with `@playwright/test` dependency

**playwright.config.ts** — Chromium only, single worker, no retries, uses `process.env.APP_PORT` for base URL, viewport `{ width: 1920, height: 1080 }`, automatic screenshot capture on failure: `screenshot: 'only-on-failure'`, trace and video recording: `trace: 'retain-on-failure'`, `video: 'retain-on-failure'` in `use`

**`<app-name>.spec.ts`** — one spec file per app found in the spec and source code:
- `beforeAll`: find free port via `net.createServer()`, spawn `dotnet run -- --port <port>`, wait for HTTP 200
- `afterAll`: kill process tree (use `execSync('taskkill /F /T /PID ' + pid)` on Windows, `serverProcess.kill()` on Unix — see Windows Process Cleanup in Memory/PlaywrightPatterns.md)
- `beforeEach`: navigate to root
- Tests should cover:
  - All UI elements specified in the spec are visible
  - Interactive elements work (buttons click, switches toggle, sliders move)
  - State changes are reflected in the UI
  - Edge cases specific to the app's logic
  - Generated/computed output appears correctly
  - Features listed in the spec are functional
  - **For apps with external API calls**: Tests should verify EITHER successful data OR error handling (see External API Error Handling below)

**Screenshots:**
- Save to `.ivy/tests/screenshots/`
- Take a screenshot at every important step with descriptive numbered filenames (e.g., `01-initial-load.png`, `02-after-click.png`)
- Use `fullPage: true`
- Keep a global counter across all tests

**Videos:**
- Playwright records a video per test automatically via `video: { mode: 'on', dir: './videos' }`
- Videos are saved to `.ivy/tests/videos/`
- After each test, rename the video to match the test name using `test.afterEach`

**Logging — this is critical:**
- Capture ALL browser console logs → write to `.ivy/tests/console.log`
- Capture ALL dotnet process stdout/stderr → write to `.ivy/tests/backend.log`
- We are specifically looking for runtime errors, unhandled exceptions, and warnings

**Runtime error detection via screenshots:**
- Runtime errors in Ivy often manifest visually — error messages, broken layouts, empty dashboards, missing data, error callouts
- After each interaction, take a screenshot and check for visual error indicators
- Look for: error toasts, `Callout.Error()` messages, blank/empty areas where content should be, stack traces rendered in the UI, "Something went wrong" messages
- If a screenshot shows a runtime error, capture it and treat it as a test failure to fix

**Code style:**
- TypeScript, clean imports
- **ES module support (CRITICAL)**: All test files MUST include this boilerplate at the top:
  ```typescript
  import { fileURLToPath } from 'url';
  import path from 'path';
  const __dirname = path.dirname(fileURLToPath(import.meta.url));
  ```
  This prevents `ReferenceError: __dirname is not defined in ES module scope` errors
- Use `getByText()`, `getByRole()` locators (accessibility-friendly)
- Use `.first()` when multiple matches possible
- Use `waitForTimeout(500)` after interactions before asserting
- On Windows use `shell: true` in spawn options
- Resolve project root: `process.cwd().replace(/[/\\]\.ivy[/\\]tests$/, "")`

**Ivy-specific locator patterns:**
- **NumberInput**: `state.ToNumberInput()` renders as `input[type="text"]`, NOT `input[type="number"]`.
  - Use `page.locator('input[type="text"]').nth(N)` to target by position
  - After `.clear()` or `.fill()`, DO NOT use `input[value="X"]` selectors — the value attribute may not update immediately
  - Prefer structural locators (position-based) over value-based selectors for number inputs
- **SelectInput**: Use `getByRole("combobox")` for the trigger, `getByText("Option", { exact: true }).first()` for options
- **Switch/Toggle**: Use `getByText()` to find the label (labels include the text content)
- **Slider**: Use `getByRole("slider")` and keyboard interactions (ArrowRight/ArrowLeft, Home/End)

**CodeBlock Output Verification:**
- When testing apps that display content in a `CodeBlock` widget (look for `new CodeBlock(...)` or `.ToCodeBlock()` in the app source):
  - CodeBlock uses syntax highlighting which wraps content in `<span>` elements
  - Exact string matching will fail for multi-character sequences
  - Use flexible assertions:
    - Split expected content into individual words/tokens and check each separately
    - Use `.includes()` with OR logic for alternative forms (encoded/decoded, formatted/raw)
    - Check for key fragments rather than exact strings
  - Example: `expect(output?.includes('keyword1') && output.includes('keyword2')).toBeTruthy();`

**External API Error Handling:**
- When apps make external API calls (OpenAI, CoinGecko, etc.), tests should handle BOTH success AND error states
- External APIs may return 401/403/rate limits due to invalid keys, network issues, or test environment configuration
- **Pattern**: Use `page.content().includes()` to detect EITHER success indicators OR error messages:
  ```typescript
  const content = await page.content();
  const hasSuccess = content.includes('expected output text') || content.includes('1.');
  const hasError = content.includes('Error') || content.includes('401') || content.includes('Forbidden');
  expect(hasSuccess || hasError).toBeTruthy();
  ```
- This makes tests resilient to external API availability while still verifying the app handles both scenarios correctly
- Error callouts render complex HTML — `page.content().includes()` is more reliable than `getByText()` for error text

If Args contains additional instructions, apply them to the test generation.

### 8. Install Dependencies

```powershell
cd .ivy/tests
vp install
```

If Playwright browsers aren't installed, run `npx playwright install chromium`.

### 9. Run Tests and Fix Loop

- Clean previous screenshots and logs before running
- Run: `cd .ivy/tests && vp run test`
- If tests pass AND logs are clean, proceed to step 10
- If tests fail, logs contain errors/warnings, or screenshots show runtime errors:
  1. Analyze the errors — test failures, console errors, backend exceptions, visual errors in screenshots
  2. Determine where the fix belongs:
     - **Test code** (wrong selectors, timing) → fix the `.spec.ts` files
     - **Project source code** (bugs in .cs files) → fix the `.cs` files in the project directory
     - **Ivy Framework or other external** → do NOT fix, note for later planning
  3. Apply fixes and re-run
  4. Record what was changed in each fix round
- Retry until tests pass, logs are clean, and screenshots show no visual errors, up to 5 rounds
- Focus: runtime errors (in logs AND visually in screenshots) are the priority, not just passing assertions

### 10. Review Screenshots → review-ux.md

View every screenshot in `.ivy/tests/screenshots/` and write `.ivy/review-ux.md`:

```markdown
# UX Review: [Project Name]

## Screenshots Reviewed

### [screenshot-name.png]

**What it shows**: [brief description]
**Issues**:
- [layout problem, alignment issue, missing spacing, etc.]
- [visual inconsistency, unclear UI, etc.]

## Recommendations

| Area | Issue | Suggestion |
|------|-------|------------|
| Layout | [e.g., content not centered] | [e.g., Use Layout.Center() wrapper] |
| Spacing | [e.g., buttons too close together] | [e.g., Add gap between action buttons] |
| Typography | [e.g., missing heading] | [e.g., Add Text.H2() title] |
| UX Flow | [e.g., no feedback on action] | [e.g., Add toast notification on copy] |

## Overall Assessment

[Brief paragraph: how does the UI look? What are the biggest improvements needed?]
```

Be specific and actionable. Reference Ivy UI components where applicable.

### 11. Generate review-tests.md

Write `.ivy\review-tests.md` in the project folder:

```markdown
# Test Review: [Project Name]

## Result

[✅ All tests passed, logs clean / ⚠️ Tests passed with warnings / ❌ Tests failed]

## Tests

| Test | Status |
|------|--------|
| [test name] | ✅ Pass / ❌ Fail |

## Log Review

### Console Logs
[Clean / list of errors and warnings found]

### Backend Logs
[Clean / list of errors, exceptions, stack traces found]

## Project Fixes Applied

[If any .cs files in the project were changed:]

### Fix N

**Problem**: [runtime error or test failure]
**File**: `[path relative to project]`
**Change**: [what was changed and why]

## External Issues (For Planning)

[Issues that require changes outside the project directory — e.g., Ivy Framework bugs, missing APIs, NuGet package issues. Include enough detail for a planning step to act on.]

| Issue | Affected Area | Details |
|-------|--------------|---------|
| [description] | [Framework / Agent / MCP / etc.] | [what needs to change and why] |
```

### 12. Summary

Present the user with:
- Project name
- Test result (PASSED / FAILED / fix rounds needed)
- Project fixes applied (if any)
- External issues noted (if any)
- UX review highlights

### Rules

- Fix issues in the project directory — that's the goal
- Do NOT modify files outside the project directory (Framework, Agent, etc.) — only note what's needed
- Runtime errors and clean logs are the primary focus
- Keep fixes minimal — only change what's needed to resolve the issue
- If a fix requires understanding Ivy Framework APIs, consult the docs and samples
