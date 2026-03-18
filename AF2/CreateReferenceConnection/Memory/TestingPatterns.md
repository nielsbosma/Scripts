# Testing Patterns for Ivy Connections

This document captures successful testing patterns discovered while testing Ivy reference connections.

## Test Structure

### Standard Test Directory Layout
```
D:\Temp\CreateReferenceConnectionTest\<ServiceName>\
├── Ivy.Connections.<ServiceName>\      # Copied connection project
│   ├── Apps\                           # Demo applications
│   ├── Connections\                    # Connection implementation
│   ├── Tests\                          # Unit tests
│   └── Program.cs                      # Ivy launcher
└── .ivy\
    └── tests\
        ├── package.json                # Playwright dependencies
        ├── playwright.config.ts        # Test configuration
        ├── connection.spec.ts          # Connection interface tests
        ├── apps.spec.ts                # Demo app tests
        ├── screenshots\                # Visual outputs
        ├── build.log                   # Build output
        ├── unit-tests.log              # Unit test results
        ├── playwright.log              # E2E test results
        └── report.md                   # Final test report
```

## Test Categories

### 1. Build Tests
**Purpose:** Verify the connection project compiles successfully.

**Pattern:**
```powershell
dotnet build
```

**Success Criteria:**
- Exit code 0
- No compilation errors
- All dependencies resolved

**Common Issues:**
- Missing NuGet packages → restore packages first
- Framework mismatch → ensure .NET 8.0+ support
- Invalid syntax → check generated code quality

### 2. Unit Tests
**Purpose:** Verify connection logic and TestConnection method.

**Pattern:**
```powershell
dotnet test --no-build --verbosity normal
```

**Success Criteria:**
- All tests pass
- No skipped tests (unless expected)
- TestConnection method works with valid credentials

**Common Issues:**
- Missing test credentials → configure in user secrets
- API rate limits → use mocks or retry logic
- Flaky tests → add proper waits and retries

### 3. Connection Interface Tests
**Purpose:** Verify IConnection implementation completeness.

**Required Methods:**
- `GetName()` - Returns friendly connection name
- `GetConnectionType()` - Returns "Reference" or custom type
- `GetSecrets()` - Returns list of required secrets
- `GetEntities()` - Returns available entities/resources
- `RegisterServices()` - Registers DI services correctly
- `TestConnection()` - Validates credentials work

**Pattern:**
```csharp
// Check that all methods exist and are public
public.*\s+GetName\s*\(
public.*\s+GetConnectionType\s*\(
public.*\s+GetSecrets\s*\(
public.*\s+GetEntities\s*\(
public.*\s+RegisterServices\s*\(
public.*\s+TestConnection\s*\(
```

### 4. Demo App Tests
**Purpose:** Verify apps launch, render, and function without errors.

**Launch Pattern:**
```bash
dotnet run -- --port 5000 --chrome=false
```

**Test Flow:**
1. Start app process
2. Wait for "Now listening on:" in stdout
3. Navigate to http://localhost:<port>
4. Wait for networkidle
5. Capture screenshot
6. Check for console errors
7. Kill process

**Success Criteria:**
- HTTP status < 400
- Page loads without exceptions
- No critical console errors (ignore favicon/DevTools)
- Screenshot captured successfully

**Common Issues:**
- Port conflicts → use dynamic ports (5000, 5001, 5002...)
- Slow startup → increase wait timeout to 30s
- Missing dependencies → check app's package references
- Credential errors → configure secrets or skip if optional

### 5. Visual Regression Tests
**Purpose:** Detect unexpected UI changes.

**Pattern:**
- Capture full-page screenshot at 1920x1920 viewport
- Store in `.ivy/tests/screenshots/<app-name>.png`
- Manual review of screenshots for quality

**Success Criteria:**
- Screenshot file exists
- File size > 1KB (not empty/error image)
- Visual inspection shows expected UI

## Playwright Configuration

### Optimal Settings
```typescript
{
  workers: 1,              // Serial execution for stability
  retries: 0,              // No retries (tests should be reliable)
  viewport: {              // Large viewport for full content
    width: 1920,
    height: 1920
  },
  trace: 'retain-on-failure',
  screenshot: 'only-on-failure',
  video: 'retain-on-failure'
}
```

### Why These Settings?
- **Single worker:** Prevents port conflicts when launching multiple apps
- **No retries:** Tests should be deterministic, flaky tests need fixing
- **Large viewport:** Captures more content in screenshots
- **Failure artifacts:** Helps debugging when tests fail

## Error Handling Patterns

### Graceful App Shutdown
Always clean up processes, even on failure:

```typescript
let appProcess: ChildProcess | null = null;
try {
  appProcess = await startApp('AppName', 5000);
  // ... test logic ...
} finally {
  if (appProcess) {
    appProcess.kill();
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
}
```

### Console Error Filtering
Ignore known harmless errors:

```typescript
const criticalErrors = consoleErrors.filter(err =>
  !err.includes('favicon') &&      // Favicon 404 is common
  !err.includes('DevTools') &&     // DevTools messages are noise
  !err.includes('autofill')        // Browser autofill warnings
);
```

### Timeout Strategy
- **App startup:** 30 seconds
- **Page navigation:** 10 seconds
- **Network idle:** 10 seconds
- **Process cleanup:** 1 second

## Test Report Structure

### Essential Sections
1. **Overall Result** - Pass/Partial/Fail summary
2. **Build Status** - Compilation success/failure
3. **Unit Tests** - Test counts and results
4. **Connection Interface** - Method presence verification
5. **Demo Apps** - Per-app results with screenshots
6. **Issues Found** - Categorized problems
7. **Recommendations** - Next steps

### Result Interpretation
- ✅ **Pass** - All tests succeeded, connection ready
- ⚠️ **Partial** - Some tests skipped, review needed
- ❌ **Fail** - Critical failures, must fix

## Best Practices

### DO:
- Test with fresh temp directory each run
- Copy entire connection project (preserves structure)
- Use absolute paths (Windows + bash quirks)
- Kill all child processes in finally blocks
- Generate detailed logs for debugging
- Take full-page screenshots
- Clean up temp directory on success

### DON'T:
- Run tests in source directory (might pollute)
- Hardcode port numbers (use dynamic allocation)
- Assume apps start instantly (wait for stdout)
- Ignore non-critical console errors (may hide bugs)
- Skip screenshot review (visual bugs are real bugs)
- Leave orphaned processes running

## Integration with CreateReferenceConnection

### Workflow Integration Points

1. **After Research Phase**
   - Ask user if they want to build + test
   - If yes, proceed to build phase

2. **After Build Phase**
   - Run full test suite automatically
   - Generate report

3. **If Tests Fail**
   - Analyze failure type
   - Enter fix loop (max 5 rounds)
   - Rerun tests after fixes

4. **Test Success**
   - Show report summary
   - Clean up temp directory
   - Mark research as validated

### Memory Updates
As you test more connections, add patterns here:
- Connection-specific quirks
- API authentication patterns
- Common NuGet package issues
- Demo app best practices
