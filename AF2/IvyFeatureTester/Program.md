# IvyFeatureTester

Test a new Ivy Framework feature by creating demo apps and running Playwright tests against them.

## Context

Read about important paths and files in ../.shared/Paths.md

## Execution Steps

### 1. Parse Feature Spec

- Args contains the feature description/spec
- Extract: feature name, widget/API names, expected props, events, and behaviors
- Identify which Ivy Framework source files are relevant

### 2. Research the Feature

- Read `Memory/PlaywrightKnowledge.md` for accumulated Ivy testing knowledge (correct APIs, gotchas, patterns)
- Read the Ivy Framework AGENTS.md for general Ivy knowledge: `D:\Repos\_Ivy\Ivy-Framework\AGENTS.md`
- Read relevant source code for the feature from `D:\Repos\_Ivy\Ivy-Framework\src\`
- Read docs if available: `D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Docs.Shared\Docs`
- Read existing samples for similar features: `D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Samples.Shared\Apps\`
- Understand the API surface: constructors, methods, properties, events

### 3. Create Temp Project

- Create folder: `D:\Temp\IvyFeatureTester\<FeatureName>\`
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
await server.RunAsync();
```

### 4. Create Demo Apps

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

### 5. Build and Verify

- Run `dotnet build` in the temp project folder
- Fix any compilation errors
- Run `dotnet run --describe` to verify all apps are registered
- Iterate until build succeeds

### 6. Create Playwright Tests

Create `.ivy/tests/` directory with:

**package.json** — minimal, with `@playwright/test` dependency

**playwright.config.ts** — Chromium only, single worker, no retries, viewport `{ width: 1920, height: 1920 }` (square format, must be set in both `use` and `projects[0].use` to override device presets), uses `process.env.APP_PORT`

**One `.spec.ts` per app:**
- `beforeAll`: find free port, spawn `dotnet run -- --port <port>`, wait for HTTP 200
- `afterAll`: kill process
- Test each app at `http://localhost:<port>/<app-id>?chrome=false`
- Take screenshots at every key step → `.ivy/tests/screenshots/`
- Use global screenshot counter with descriptive names
- Capture browser console logs → `.ivy/tests/console.log`
- Capture backend stdout/stderr → `.ivy/tests/backend.log`

**Test coverage must verify:**
1. Feature renders correctly (visual via screenshots)
2. All props produce expected visual output
3. All events fire correctly (check state feedback text)
4. Feature integrates well with other widgets
5. No console errors or warnings
6. No backend errors or exceptions
7. No visual error indicators (error toasts, callouts, blank areas)

**Code patterns (from PlaywrightKnowledge.md):**
- Use `getByText()`, `getByRole()` locators
- Use `.first()` when multiple matches possible
- Use `waitForTimeout(500)` after interactions
- On Windows use `shell: true` in spawn options
- Resolve project root: `process.cwd().replace(/[/\\]\.ivy[/\\]tests$/, "")`
- Wait for server ready by polling HTTP, not just stdout

### 7. Install & Run Tests

```bash
cd .ivy/tests
npm install
npx playwright install chromium  # if needed
npx playwright test
```

### 8. Fix Loop #1 (up to 10 rounds)

If tests fail, logs have errors, or screenshots show issues:

1. Analyze failures — categorize as:
   - **Test code issue** → fix `.spec.ts`
   - **Demo app issue** → fix `.cs` files in temp project
   - **Bug in the tester framework feature** → Fix 
   - **General framework bug** → Fix by reporting to D:\Repos\_Ivy\.plans\ (see instructions below)
2. Apply fixes and re-run
3. Track each fix round

### 9. Visual Quality Review

Review all screenshots and verify:
- Does the feature look consistent with other Ivy features?
- Is spacing, alignment, typography correct?
- Does it follow Ivy's design patterns?
- Would a user find this intuitive?

Write `.ivy/review-ux.md` with findings.

### 10. Feature Verification Report

Write `.ivy/review-feature.md`:

```markdown
# Feature Test Report: [Feature Name]

## Result
[✅ Feature works as intended / ⚠️ Partial / ❌ Failed]

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

### 8. Fix Loop #2 UX/Functionality (up to 3 rounds)

Baed on review-feature.md and review-ux.md, try to fix and rerun the entire process until perfect.

1. Analyze
2. Apply fixes and re-run
3. Track each fix round

### 11. Summary

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