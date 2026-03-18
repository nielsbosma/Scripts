# CreateReferenceConnection

> **⚠️ READ-ONLY MODE: You must NEVER create, edit, or delete any files outside of `D:\Repos\_Ivy\Ivy\connections\.research\`. You may only READ source files. The ONLY files you are allowed to write are research markdown files in `.research\`.**

Research and document a new reference connection for the Ivy ecosystem following the established pattern.

## Context

Reference connections are third-party API integrations that Ivy can use. Each connection gets its own research document in `D:\Repos\_Ivy\Ivy\connections\.research\` describing the service, available NuGet packages, OpenAPI specs, authentication, and how to obtain API keys.

The research phase is critical to ensure we select the best implementation approach before creating the actual connection implementation.

## Execution Steps

### 1. Parse Args

Args should contain the name of the service to research (e.g., "Stripe", "Twilio", "SendGrid").

### 2. Research Phase

Create a comprehensive markdown file at `D:\Repos\_Ivy\Ivy\connections\.research\<ServiceName>.md` that includes:

#### A. Service Overview
- Brief description of what the service does
- Primary use cases
- Official website and documentation links

#### B. NuGet Package Analysis

Search for available .NET packages for this service. For each candidate package, evaluate:

**GOOD indicators:**
- Many downloads (10,000+)
- Recently updated (within last 6 months)
- Copyleft license (MIT, Apache, etc.)
- Good documentation
- Official package created by the service provider
- Support for IChatClient (if applicable for AI services)
- Multi-framework support (.NET 8.0, .NET Standard 2.0, etc.)
- Active GitHub repository with stars and contributors

**BAD indicators:**
- Few downloads (<1,000)
- Not updated in a long time (>1 year)
- Restrictive license (GPL, etc.)
- No documentation
- Abandoned or unmaintained
- Third-party with no official alternative

For each package include:
- Package name and NuGet link
- Version number
- Download count
- Last update date
- License type
- Target frameworks
- Dependencies
- Project URL
- Documentation URL
- Official vs Third-Party status
- GitHub stars/contributors (if available)
- Notes about special features or limitations

**Recommendation:** Clearly state which package is recommended and why. If there's no good NuGet package, recommend using the OpenAPI spec with a code generator (NSwag, Kiota, or AutoRest).

#### C. OpenAPI / Swagger Specification

Search for an official OpenAPI/Swagger specification:
- OpenAPI JSON URL
- OpenAPI YAML URL
- Interactive API documentation URL
- GitHub repository for the spec (if available)
- Note whether it's OpenAPI 2.0 or 3.x

If an OpenAPI spec exists, mention that it can be used to generate a client.

#### D. Required Secrets / API Keys

Document what authentication credentials are needed:
- Type of authentication (API key, OAuth, Bearer token, etc.)
- Secret names (e.g., `API_KEY`, `CLIENT_ID`, `CLIENT_SECRET`)
- Format of the secrets
- Whether they expire
- Scope/permissions available
- Security features (rotation, expiration, compromise detection, etc.)

**IMPORTANT:** We're looking for **server-side API keys** that can be used on a backend server, NOT OAuth user authentication flows.

#### E. How to Obtain Secrets / API Keys

Provide **step-by-step instructions** for developers to get these secrets:

1. Account creation process (signup URL, requirements)
2. Navigation to API/integration settings (exact URLs)
3. Creating/generating API keys
4. Configuring permissions/scopes (if applicable)
5. Copying and storing the secrets securely
6. How to use the secrets (environment variables, configuration)
7. How to verify the secrets work
8. Token rotation/refresh process (if applicable)

Be specific with URLs, button names, and menu paths so someone can follow along easily.

### 3. Validation

Before finalizing, verify:
- [ ] All URLs are valid and accessible
- [ ] NuGet package information is current
- [ ] API documentation links work
- [ ] The recommended package is clearly stated with justification
- [ ] Step-by-step secret acquisition is complete and actionable
- [ ] The document follows the format of existing research files (see `Apify.md`, `Cohere.md` as examples)

### 4. Existing Connection Check

Before finalizing, check if a connection already exists:
- Check if `D:\Repos\_Ivy\Ivy\connections\<ServiceName>\` exists
- If it exists, still create/update the research file but note in the summary that implementation already exists

### 3. Build Phase (Optional)

After research is complete, optionally build the connection:

- [ ] Ask user if they want to proceed with building the connection implementation
- [ ] If yes, trigger the CreateReferenceConnectionWorkflow via the Ivy Agent
- [ ] Wait for workflow completion
- [ ] Proceed to testing phase

### 4. Testing Phase

Create comprehensive tests to verify the connection implementation:

- [ ] Create `D:\Temp\CreateReferenceConnectionTest\<ServiceName>\` test directory
- [ ] Copy the generated connection project from `D:\Repos\_Ivy\Ivy\connections\<ServiceName>\Ivy.Connections.<ServiceName>\`
- [ ] Create `.ivy/tests/` directory structure:
   - `package.json` with Playwright dependencies
   - `playwright.config.ts` (Chromium, single worker, 1920x1920 viewport)
   - `connection.spec.ts` for connection tests
   - `apps.spec.ts` for demo app tests

**Test Coverage:**

1. **Build Test** - Verify `dotnet build` succeeds
2. **Unit Tests** - Run `dotnet test` and verify all unit tests pass
3. **Connection Test** - Verify connection class:
   - Implements IConnection interface
   - GetName() returns expected name
   - GetConnectionType() returns correct type
   - GetSecrets() returns expected secrets
   - GetEntities() returns valid entities
   - RegisterServices() registers services without errors
4. **App Tests** - For each demo app:
   - Launch with `dotnet run -- --port <port> --chrome=false`
   - Navigate to app URL
   - Verify app renders without console errors
   - Take screenshot at `.ivy/tests/screenshots/<app-name>.png`
   - Capture backend logs to `.ivy/tests/backend.log`
   - Capture browser console to `.ivy/tests/console.log`
5. **Integration Test** (if credentials available):
   - Call TestConnection() method
   - Verify it returns success
   - If available, test a simple API call through the client

- [ ] Run tests and collect results
- [ ] Review all screenshots for visual quality
- [ ] Check logs for errors or warnings

### 5. Fix Loop

If tests fail:
1. Analyze the failure type (build error, runtime error, visual issue, API error)
2. Determine if it's:
   - A bug in the generated connection code → create a plan to fix the workflow
   - Missing credentials → prompt user to configure secrets
   - A test issue → fix the test code
   - Expected behavior → document as a known limitation
3. Apply fixes and rerun tests (max 5 rounds)

### 6. Report

Generate a comprehensive test report at `.ivy/tests/report.md`:

```markdown
# Connection Test Report: <ServiceName>

## Result
[✅ All tests passed / ⚠️ Partial / ❌ Failed]

## Build Status
[Pass/Fail with details]

## Unit Tests
[Pass/Fail with count]

## Connection Interface
| Method | Status | Notes |
|--------|--------|-------|
| GetName | Pass/Fail | |
| GetConnectionType | Pass/Fail | |
| GetSecrets | Pass/Fail | |
| GetEntities | Pass/Fail | |
| RegisterServices | Pass/Fail | |
| TestConnection | Pass/Fail | |

## Demo Apps
| App | Build | Launch | Render | Console Clean | Backend Clean | Screenshot |
|-----|-------|--------|--------|---------------|---------------|------------|

## Issues Found
| Issue | Severity | Area | Details |
|-------|----------|------|---------|

## Recommendations
[Any suggestions for improvement]
```

### Rules

- **!CRITICAL: This agent is READ-ONLY for all source code. You must NEVER use Edit, Write, or Bash to create, modify, or delete any file outside `D:\Repos\_Ivy\Ivy\connections\.research\`.**
- Research must be thorough and accurate
- Follow the established format from existing research files
- Always recommend the best option with clear justification
- Include all relevant URLs and version information
- Make the "How to Obtain Secrets" section actionable and detailed
- If the service has multiple authentication methods, document all of them
- Note if certain features require paid plans or special access
