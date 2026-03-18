# Common Issues in Connection Testing

This document tracks frequent problems encountered when testing Ivy connections and their solutions.

## Build Issues

### Issue: NuGet Package Not Found
**Symptoms:**
```
error NU1101: Unable to find package 'PackageName'. No packages exist with this id
```

**Root Causes:**
- Package name typo in research
- Package doesn't exist on NuGet.org
- Package was removed or unlisted
- Wrong package source configured

**Solutions:**
1. Verify package exists on nuget.org
2. Check package name spelling
3. Add correct package source to NuGet.config
4. Use alternative package or OpenAPI generation

**Prevention:**
- Validate package URLs during research phase
- Check "Last Updated" date (avoid unmaintained packages)
- Verify download count (low downloads = suspicious)

---

### Issue: Target Framework Mismatch
**Symptoms:**
```
error NU1202: Package 'PackageName' is not compatible with net8.0
```

**Root Causes:**
- Package only supports older frameworks (.NET Framework, .NET Core 3.1)
- Package targets newer frameworks (.NET 9.0+)
- Multi-targeting configuration error

**Solutions:**
1. Check package's supported frameworks on NuGet
2. Use a different package version
3. Multi-target the connection project
4. Generate client from OpenAPI spec instead

**Prevention:**
- Document target frameworks in research phase
- Prefer packages with broad framework support
- Test with .NET 8.0+ (current Ivy standard)

---

### Issue: Circular Dependency
**Symptoms:**
```
error CS0234: Circular dependency detected
```

**Root Causes:**
- Workflow generated incorrect project references
- Connection references itself
- Dependency graph cycle

**Solutions:**
1. Review .csproj files for incorrect references
2. Check Program.cs for proper project structure
3. Regenerate connection with workflow fixes

**Prevention:**
- Validate generated project structure
- Review CreateReferenceConnectionWorkflow output

---

## Unit Test Issues

### Issue: TestConnection Fails with "Unauthorized"
**Symptoms:**
```
Test Failed: TestConnection returned false
Expected: True
Actual: False
```

**Root Causes:**
- No credentials configured
- Invalid/expired API keys
- Wrong secret names in configuration
- API endpoint changed

**Solutions:**
1. Configure user secrets: `dotnet user-secrets set API_KEY "value"`
2. Verify secrets match GetSecrets() method
3. Test credentials directly with API
4. Check API documentation for endpoint changes

**Prevention:**
- Document exact secret names in research
- Include "How to Obtain Secrets" steps
- Add credential validation to TestConnection

---

### Issue: Rate Limit Exceeded
**Symptoms:**
```
Test Failed: API returned 429 Too Many Requests
```

**Root Causes:**
- Free tier rate limits
- Running tests repeatedly
- Multiple connections using same API key

**Solutions:**
1. Add delays between test runs
2. Use mock responses for frequent tests
3. Implement retry logic with exponential backoff
4. Use test/sandbox API endpoints

**Prevention:**
- Document rate limits in research
- Use caching for repeated calls
- Implement graceful degradation

---

### Issue: Flaky Tests
**Symptoms:**
- Tests pass sometimes, fail other times
- Timeouts in CI but pass locally

**Root Causes:**
- Network latency
- External API instability
- Race conditions
- Insufficient waits

**Solutions:**
1. Increase timeouts (especially in CI)
2. Add retry logic for network calls
3. Use proper async/await patterns
4. Mock external dependencies

**Prevention:**
- Write deterministic tests
- Avoid time-sensitive assertions
- Use dependency injection for testing

---

## Demo App Issues

### Issue: Port Already in Use
**Symptoms:**
```
Error: Failed to bind to address http://localhost:5000
```

**Root Causes:**
- Previous test didn't clean up
- Another service using same port
- Orphaned process from crashed test

**Solutions:**
1. Use dynamic port allocation (5000, 5001, 5002...)
2. Kill all `dotnet` processes before testing
3. Implement proper process cleanup in tests

**Prevention:**
- Always use unique ports per app
- Kill processes in finally blocks
- Check port availability before binding

---

### Issue: App Fails to Start
**Symptoms:**
- Process exits immediately
- No "Now listening on:" message
- Timeout waiting for startup

**Root Causes:**
- Missing dependencies
- Configuration error
- Unhandled exception during startup
- Wrong working directory

**Solutions:**
1. Check stderr output for errors
2. Run `dotnet build` first
3. Verify appsettings.json exists
4. Check Program.cs initialization

**Prevention:**
- Validate app structure in build phase
- Add startup logging
- Handle exceptions in Startup.cs

---

### Issue: Console Errors in Browser
**Symptoms:**
```
Uncaught TypeError: Cannot read property 'X' of undefined
Failed to load resource: net::ERR_BLOCKED_BY_CLIENT
```

**Root Causes:**
- JavaScript errors in Blazor components
- Missing static files
- Ad blockers blocking resources
- CORS issues

**Solutions:**
1. Filter known harmless errors (favicon, DevTools)
2. Fix JavaScript errors in components
3. Verify static files are bundled
4. Configure CORS properly

**Prevention:**
- Test in clean browser profile
- Validate JavaScript at build time
- Include all static assets in project

---

### Issue: Screenshots Empty or Corrupted
**Symptoms:**
- Screenshot file < 1KB
- Image shows error page
- File exists but is blank

**Root Causes:**
- Page didn't fully load
- Network timeout
- App crashed after screenshot
- Viewport too small

**Solutions:**
1. Wait for networkidle before screenshot
2. Increase navigation timeout
3. Check app logs for errors
4. Use full-page screenshot option

**Prevention:**
- Always wait for page load events
- Capture screenshots last (after all tests)
- Use large viewport (1920x1920)

---

## Playwright Issues

### Issue: Browser Not Installed
**Symptoms:**
```
Error: browserType.launch: Executable doesn't exist
```

**Root Causes:**
- Playwright browsers not installed
- Wrong Playwright version
- Installation failed silently

**Solutions:**
1. Run `npx playwright install chromium --with-deps`
2. Check npm install output for errors
3. Verify disk space available

**Prevention:**
- Install browsers before running tests
- Document installation steps clearly
- Check for installation errors

---

### Issue: Navigation Timeout
**Symptoms:**
```
TimeoutError: page.goto: Timeout 30000ms exceeded
```

**Root Causes:**
- App takes too long to start
- Network issues
- App stuck in infinite loop
- Wrong URL

**Solutions:**
1. Increase navigation timeout to 60s
2. Check app actually started (curl localhost:port)
3. Review app logs for errors
4. Verify correct URL format

**Prevention:**
- Use realistic timeouts (30-60s for cold start)
- Wait for app stdout before navigating
- Log all URLs being tested

---

## Workflow Integration Issues

### Issue: Workflow Not Found
**Symptoms:**
- Cannot trigger CreateReferenceConnectionWorkflow
- Workflow execution fails

**Root Causes:**
- Workflow not published
- Wrong workflow name
- Ivy agent not configured

**Solutions:**
1. Verify workflow exists in Ivy
2. Check workflow name matches exactly
3. Configure Ivy agent properly

**Prevention:**
- Document workflow names in WorkflowIntegration.md
- Test workflow trigger before full automation

---

## Fix Loop Strategies

### When to Fix Automatically
- Build errors (missing imports, syntax)
- Port conflicts (allocate different port)
- Missing files (regenerate or create)
- Configuration issues (appsettings, secrets)

### When to Prompt User
- Missing API credentials
- Workflow bugs (need workflow fix)
- API changes (require research update)
- Ambiguous errors (need human judgment)

### When to Skip
- Expected limitations (free tier restrictions)
- Known issues (documented quirks)
- Non-critical warnings (favicon 404)

### Max Retry Strategy
- Maximum 5 fix rounds
- Track what was attempted
- Don't retry same fix twice
- Escalate to user after max retries

---

## Logging Best Practices

### What to Log
- ✅ Build output (full)
- ✅ Unit test results (full)
- ✅ App stdout/stderr (full)
- ✅ Browser console (errors only)
- ✅ Playwright results (full)

### What NOT to Log
- ❌ Secrets/API keys
- ❌ Full request/response bodies (may contain PII)
- ❌ Excessive debug output

### Log File Organization
```
.ivy/tests/
├── build.log          # dotnet build output
├── unit-tests.log     # dotnet test output
├── playwright.log     # test runner output
├── backend.log        # app stdout/stderr (if needed)
└── console.log        # browser console (if needed)
```

---

## Update Instructions

As you encounter new issues while testing connections:

1. Add the issue with symptoms
2. Document root causes
3. Provide concrete solutions
4. Include prevention strategies
5. Link to related resources if available

Keep this document up-to-date to reduce debugging time for future connections.
