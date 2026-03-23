# IvyFeatureTester

Test a new Ivy Framework feature by creating demo apps and running Playwright tests against them.

## Context

Read about important paths and files in ../.shared/Paths.md

## Execution Steps

### 1. Parse Feature Spec

- Args contains the feature description/spec
- Extract: feature name, widget/API names, expected props, events, and behaviors
- Identify which Ivy Framework source files are relevant
- **Set terminal title** to the extracted feature name for easy tab identification:
  ```bash
  echo -ne "\033]0;IFT: <FeatureName>\007"
  ```

### 2. Research the Feature

- Read `Memory/PlaywrightKnowledge.md` for accumulated Ivy testing knowledge (correct APIs, gotchas, patterns)
- Read the Ivy Framework AGENTS.md for general Ivy knowledge: `D:\Repos\_Ivy\Ivy-Framework\AGENTS.md`
- **Search plan context for recent related work:**
  - Use Glob to list files in `D:\Repos\_Ivy\.plans\completed\`, `D:\Repos\_Ivy\.plans\review\`, and `D:\Repos\_Ivy\.plans\logs\`
  - Use Grep to search for the feature name or related widget names across those directories
  - Read the most relevant 3-5 plan files (prioritize review > completed for currency)
  - If a specific commit is referenced in Args, search for plans that mention that commit ID
  - Extract key insights: known issues, workarounds, design decisions, implementation patterns
  - Use this context to inform test app creation and edge case selection
- Read relevant source code for the feature from `D:\Repos\_Ivy\Ivy-Framework\src\`
- Read docs if available: `D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared\Docs`
- Read existing samples for similar features: `D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Samples.Shared\Apps\`
- Understand the API surface: constructors, methods, properties, events

### 3. Verify Completeness (Widgets Only)

If the feature being tested is a **widget**, check that required companion artifacts exist:

1. **Sample App**: Search `D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Samples.Shared\Apps\` for files containing the widget name
2. **Documentation Page**: Search `D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared\Docs\02_Widgets\` subdirectories for a matching `.md` file

Record the results — they will be included in the Feature Verification Report (Step 11). If either artifact is missing, it will be flagged as a warning.

Skip this step for non-widget features (utilities, services, non-visual APIs).

### 4. Create Temp Project

- Create folder: `D:\Temp\IvyFeatureTester\<yyyy-MM-dd>\<FeatureName>\` where `<yyyy-MM-dd>` is the current date (e.g., `2026-03-19`)
- Create a new Ivy project:

**`<FeatureName>.csproj`:**
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="D:\Repos\_Ivy\Ivy-Framework\src\Ivy\Ivy.csproj" />
    <ProjectReference Include="D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Analyser\Ivy.Analyser.csproj" OutputItemType="Analyzer" ReferenceOutputAssembly="false" />
  </ItemGroup>
</Project>
```

**`Program.cs`:**
```csharp
using Ivy;
using System.Reflection;

var server = new Server();
server.AddAppsFromAssembly(Assembly.GetExecutingAssembly());
server.UseChrome();
await server.RunAsync();
```

### 5. Create Demo Apps

Create multiple `.cs` app files that exercise the feature comprehensively:

- **BasicApp** — Simplest usage of the feature, demonstrating core functionality
- **PropsApp** — Tests all props/configuration options with visible output for each
- **EventsApp** — Tests all events (OnClick, OnChange, etc.) with state feedback showing the event fired
- **IntegrationApp** — Combines the feature with other common Ivy widgets (layouts, cards, etc.)
- **EdgeCasesApp** — Tests edge cases: empty values, large data, rapid interactions

Each app must:
- Inherit from `ViewBase` (NOT `AppBase`)
- Have `[App]` attribute with descriptive title and appropriate icon
- Show clear labels for what each section tests
- Display state changes visibly so Playwright can verify them
- Follow patterns from `D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Samples.Shared\Apps\`

### 6. Build and Verify

- Run `dotnet build` in the temp project folder
- Fix any compilation errors
- Run `dotnet run --describe` to verify all apps are registered
- Iterate until build succeeds

### 7. Create Playwright Tests

Create `.ivy/tests/`, `.ivy/tests/screenshots/`, and `.ivy/tests/videos/` directories with:

**package.json** — minimal, with `@playwright/test` dependency

**playwright.config.ts** — Chromium only, single worker, no retries, viewport `{ width: 1920, height: 1920 }` (square format, must be set in both `use` and `projects[0].use` to override device presets), uses `process.env.APP_PORT`, video recording enabled: `video: { mode: 'on', dir: './videos' }` in both `use` and `projects[0].use`

**One `.spec.ts` per app:**
- `beforeAll`: find free port, spawn `dotnet run -- --port <port>`, wait for HTTP 200
- `afterAll`: kill process
- Test each app at `http://localhost:<port>/<app-id>?chrome=false`
- Take screenshots at every key step → `.ivy/tests/screenshots/`
- Use global screenshot counter with descriptive names
- Capture browser console logs → `.ivy/tests/console.log`
- Capture backend stdout/stderr → `.ivy/tests/backend.log`

**Videos:**
- Playwright records a video per test automatically via `video: { mode: 'on', dir: './videos' }` in the config
- Videos are saved to `.ivy/tests/videos/`
- After each test, save the video with a descriptive name matching the test:
  ```typescript
  test.afterEach(async ({ page }, testInfo) => {
    const video = page.video();
    if (video) {
      const videoPath = await video.path();
      const targetName = testInfo.title.replace(/[^a-zA-Z0-9]/g, '-').toLowerCase();
      const targetPath = path.join(__dirname, 'videos', `${targetName}.webm`);
      await fs.promises.mkdir(path.dirname(targetPath), { recursive: true });
      await fs.promises.copyFile(videoPath, targetPath);
    }
  });
  ```
- Videos provide evidence for interaction flows, animations, and timing-dependent behaviors

**Test coverage must verify:**
1. Feature renders correctly (visual via screenshots)
2. All props produce expected visual output
3. All events fire correctly (check state feedback text)
4. Feature integrates well with other widgets
5. No console errors or warnings
6. No backend errors or exceptions
7. No visual error indicators (error toasts, callouts, blank areas)
8. Video captures show smooth interactions without glitches

**Code patterns (from PlaywrightKnowledge.md):**
- Use `getByText()`, `getByRole()` locators
- Use `.first()` when multiple matches possible
- Use `waitForTimeout(500)` after interactions
- On Windows use `shell: true` in spawn options
- Resolve project root: `process.cwd().replace(/[/\\]\.ivy[/\\]tests$/, "")`
- Wait for server ready by polling HTTP, not just stdout

### 8. Install & Run Tests

```bash
cd .ivy/tests
npm install
npx playwright install chromium  # if needed
npx playwright test
```

### 9. Fix Loop #1 (up to 10 rounds)

If tests fail, logs have errors, or screenshots show issues:

1. Analyze failures — categorize as:
   - **Test code issue** → fix `.spec.ts`
   - **Demo app issue** → fix `.cs` files in temp project
   - **Bug in the tester framework feature** → Fix 
   - **General framework bug** → Fix by reporting to D:\Repos\_Ivy\.plans\ (see instructions below)
2. Apply fixes and re-run
3. Track each fix round

### 10. Visual Quality Review

Review all screenshots and verify:
- Does the feature look consistent with other Ivy features?
- Is spacing, alignment, typography correct?
- Does it follow Ivy's design patterns?
- Would a user find this intuitive?

Write `.ivy/review-ux.md` with findings.

### 11. Feature Verification Report

Write `.ivy/review-feature.md`:

```markdown
# Feature Test Report: [Feature Name]

## Result
[✅ Feature works as intended / ⚠️ Partial / ❌ Failed]

## Completeness (Widgets Only)
| Artifact | Status | Path |
|----------|--------|------|
| Sample App | Found/Missing | path or N/A |
| Documentation | Found/Missing | path or N/A |

## Props Tested
| Prop | Status | Notes |
|------|--------|-------|

## Events Tested
| Event | Status | Notes |
|-------|--------|-------|

## Visual Quality
[Assessment of how it looks compared to other Ivy features]

## Log Cleanliness
### Frontend Console
[Clean / issues found]

### Backend Logs
[Clean / issues found]

## Issues Found
| Issue | Severity | Area | Details |
|-------|----------|------|---------|

## Recommendations
[Any suggestions for improvement]
```

If the feature is a widget, include the Completeness section with results from Step 3. Any missing artifact should also be added to the Issues Found table with severity "Medium".

### 12. Fix Loop #2 UX/Functionality (up to 3 rounds)

Based on review-feature.md and review-ux.md, try to fix and rerun the entire process until perfect.

1. Analyze
2. Apply fixes and re-run
3. Track each fix round

### 13. Summary

Present:
- Feature name
- Test result (PASSED / FAILED / rounds needed)
- Props/events coverage
- Visual quality assessment
- Issues found (if any)
- Path to temp project and screenshots

### Rules

- Always read the actual Ivy Framework source for the feature — don't guess APIs
- Create apps that are visually clear and testable (labels, state feedback)
- Runtime errors and clean logs are critical verification criteria
- Keep demo apps focused — each tests a specific aspect
- If a feature has too many props, split into multiple apps
- Screenshots are evidence — take many, with descriptive names

### Plans

For larger issue that might need human decision make a proposed plan in D:\Repos\_Ivy\.plans\. Trigger D:\Repos\_Personal\Scripts\AF2\MakePlan.ps1 with a propt to do this. 