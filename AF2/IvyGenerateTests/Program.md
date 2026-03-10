Generate and run Playwright end-to-end tests for an Ivy Framework .NET web application.

## Context

The user's working directory is provided in the Firmware header as `WorkingDirectory`. This is the Ivy project root (contains a `.csproj` and `Program.cs`). If Args specifies a different project path, use that instead. All project-relative paths are relative to WorkingDirectory, not your script directory.

## Execution Steps

### 1. Validate Ivy Project

- Confirm the working directory (or Args path) contains a `.csproj` file and `Program.cs`
- If not, report the error and stop
- Identify the project name from the `.csproj` filename

### 2. Collect Project Source

- Read all `.cs` and `.csproj` files recursively (excluding `bin/`, `obj/`, `.ivy/` directories)
- These provide context for understanding what the app does

### 3. Read Memory

- Read all files in your `/Memory/` folder — this is your accumulated knowledge about Ivy testing patterns
- Apply these learnings when generating tests

### 4. Check Existing Tests

- Look in `.ivy/tests/` within the project for existing `.spec.ts` files
- If they exist, read them — improve or extend, do not duplicate
- Also check for `review.md`, `console.log`, `backend.log` from previous runs — these contain issues to address

### 5. Create Test Directory

- Ensure `.ivy/tests/` and `.ivy/tests/screenshots/` directories exist in the project

### 6. Generate Tests

Write the following files directly to `.ivy/tests/`:

**package.json** — minimal, with `@playwright/test` dependency

**playwright.config.ts** — Chromium only, single worker, no retries, uses `process.env.APP_PORT` for base URL

**`<app-name>.spec.ts`** — one spec file per app found in the source code:
- `beforeAll`: find free port via `net.createServer()`, spawn `dotnet run -- --port <port>`, wait for HTTP 200
- `afterAll`: kill process
- `beforeEach`: navigate to root
- Tests should cover:
  - All UI elements are visible (text, labels, buttons, inputs)
  - Interactive elements work (buttons click, switches toggle, sliders move)
  - State changes are reflected in the UI
  - Edge cases specific to the app's logic
  - Generated/computed output appears correctly

**Screenshots:**
- Save to `.ivy/tests/screenshots/`
- Take a screenshot at every important step with descriptive numbered filenames (e.g., `01-initial-load.png`, `02-after-click.png`)
- Use `fullPage: true`
- Keep a global counter across all tests

**Logging:**
- Capture browser console logs → write to `.ivy/tests/console.log`
- Capture dotnet process stdout/stderr → write to `.ivy/tests/backend.log`

**Code style:**
- TypeScript, clean imports
- Use `getByText()`, `getByRole()` locators (accessibility-friendly)
- Use `.first()` when multiple matches possible
- Use `waitForTimeout(500)` after interactions before asserting
- On Windows use `shell: true` in spawn options
- Resolve project root: `process.cwd().replace(/[/\\]\.ivy[/\\]tests$/, "")`

If Args contains additional instructions, apply them to the test generation.

### 7. Install Dependencies

```powershell
cd .ivy/tests
npm install
```

If Playwright browsers aren't installed, run `npx playwright install chromium`.

### 8. Run Tests (Fix Loop)

- Clean previous screenshots and logs before running
- Run: `cd .ivy/tests && npx playwright test`
- If tests pass, proceed to step 9
- If tests fail, analyze the errors:
  - If the issue is in test code (wrong selectors, timing), fix the `.spec.ts` files
  - If the issue is in the Ivy source code, fix the `.cs` files in the project
  - Record what source files were changed in each fix round
- Retry up to 3 times
- If a fix round changes Ivy source files, note these changes for the log

### 9. Verify Screenshots and Logs

If tests passed and screenshots exist:
- View each screenshot — check for blank pages, broken layouts, missing components, error dialogs
- Review `console.log` for runtime errors, unhandled exceptions, warnings
- Review `backend.log` for errors or stack traces
- If issues found, write a `review.md` in `.ivy/tests/` with details

### 10. Summary

Present the user with:
- Project name
- Files generated
- Test result (PASSED / FAILED / fix rounds needed)
- Any source code fixes applied
- Any issues found in screenshot/log review
