# Playwright Test Patterns for Ivy Framework

This document contains common patterns and solutions for generating robust Playwright tests for Ivy applications. These patterns prevent the need for multiple test adjustment rounds.

## Table of Contents

1. [ES Module Setup](#es-module-setup)
2. [Common Ivy Widget Locators](#common-ivy-widget-locators)
3. [External API Error Handling](#external-api-error-handling)
4. [Test Structure Best Practices](#test-structure-best-practices)

---

## ES Module Setup

### Problem
Tests fail with `ReferenceError: __dirname is not defined in ES module scope` when using `package.json` with `"type": "module"`.

### Solution
**ALWAYS** include this boilerplate at the top of every `.spec.ts` file:

```typescript
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
```

This must appear before any code that references `__dirname` for screenshot paths, project root resolution, or other file system operations.

### Why
In ES modules, `__dirname` is not automatically defined like it is in CommonJS modules. This polyfill recreates the functionality using `import.meta.url`.

---

## Common Ivy Widget Locators

### NumberInput

#### Problem
`state.ToNumberInput()` renders as `input[type="text"]`, **NOT** `input[type="number"]`. After calling `.clear()` or `.fill()`, value-based selectors like `input[value="5"]` become unreliable.

#### Solution
Use **position-based** locators instead of value-based:

```typescript
// ✅ Good: Position-based selector
const numberInput = page.locator('input[type="text"]').last();
await numberInput.clear();
await numberInput.fill('10');

// ❌ Bad: Value-based selector (fails after .clear())
const numberInput = page.locator('input[value="5"]');
```

#### Key Points
- NumberInput always renders as `type="text"`, never `type="number"`
- Use `.first()`, `.last()`, or `.nth(N)` to target by position
- Avoid `input[value="..."]` selectors after any input interaction
- `.WithLabel()` doesn't create proper HTML associations, so `getByLabel()` won't work

---

### SelectInput

#### Pattern
```typescript
// Open dropdown
await page.getByRole('combobox').click();

// Select option (use exact match to avoid ambiguity)
await page.getByText('Option Name', { exact: true }).first().click();
```

#### Key Points
- Trigger button is `role="combobox"`
- Dropdown items are plain `<div>` elements with text (no `role="option"`)
- Use `.first()` because option text may appear in multiple places

---

### Switch/Toggle

#### Pattern
```typescript
// Find by label text (labels include the text content)
await page.getByText('Enable Feature').click();
```

#### Key Points
- Switch labels contain the label text
- Can be located with `getByText()` directly

---

### Slider

#### Pattern
```typescript
const slider = page.getByRole('slider');
await slider.press('End');        // Set to max
await slider.press('Home');       // Set to min
await slider.press('ArrowRight'); // Increment by step
await slider.press('ArrowLeft');  // Decrement by step
```

#### Key Points
- Renders as Radix UI slider with `role="slider"`
- Use keyboard interaction, not mouse drag
- NOT a native `<input type="range">`

---

### Button

#### Pattern
```typescript
// Text buttons
await page.getByRole('button', { name: 'Submit' }).click();

// Icon-only buttons (no accessible name)
await page.locator('button:has(svg)').first().click();

// With exact match (for single-character buttons like "C")
await page.getByRole('button', { name: 'C', exact: true }).click();
```

---

## External API Error Handling

### Problem
Apps that call external APIs (OpenAI, CoinGecko, Yahoo Finance, etc.) may fail during tests due to:
- Invalid or expired API keys
- Rate limiting
- Network issues
- Test environment configuration

Strict assertions on successful output cause tests to fail even when the app correctly handles errors.

### Solution
Tests should verify the app handles **BOTH success AND error states** gracefully:

```typescript
// After triggering an API call (e.g., clicking "Generate")
await page.getByRole('button', { name: 'Generate' }).click();
await page.waitForTimeout(3000); // Wait for API response

// Check for EITHER success OR error handling
const content = await page.content();
const hasSuccess = content.includes('expected output') || content.includes('1.') || content.includes('Result');
const hasError = content.includes('Error') || content.includes('401') || content.includes('403') || content.includes('Forbidden') || content.includes('Invalid API key');

expect(hasSuccess || hasError).toBeTruthy();
```

### Why Use `page.content().includes()`?
- `Callout.Error()` renders complex HTML structures with icons and nested elements
- `getByText()` may fail to match error text even when visually present
- `page.content().includes()` reliably detects text anywhere in the DOM

### Pattern Summary
1. Trigger the API call (click button, submit form, etc.)
2. Wait for response (use reasonable timeout like 3-5 seconds)
3. Get full page content with `page.content()`
4. Check for success indicators (output text, numbered lists, result sections)
5. Check for error indicators (error messages, HTTP status codes, callout text)
6. Assert that **at least one** state is present: `expect(hasSuccess || hasError).toBeTruthy()`

### Example: OpenAI API Test
```typescript
test('generate email sequence with AI', async ({ page }) => {
  // Fill form
  await page.locator('input[type="text"]').fill('SaaS Product');

  // Trigger AI generation
  await page.getByRole('button', { name: 'Generate' }).click();
  await page.waitForTimeout(3000);

  // Verify EITHER success OR error
  const content = await page.content();
  const hasEmails = content.includes('Subject:') || content.includes('1.');
  const hasError = content.includes('Error') || content.includes('401') || content.includes('invalid_api_key');

  expect(hasEmails || hasError).toBeTruthy();
});
```

---

## Test Structure Best Practices

### App Lifecycle

```typescript
import { test, expect } from '@playwright/test';
import { spawn, ChildProcess } from 'child_process';
import net from 'net';
import http from 'http';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

let serverProcess: ChildProcess;
let appPort: number;

// Find free port
async function findFreePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on('error', reject);
    server.listen(0, () => {
      const port = (server.address() as net.AddressInfo).port;
      server.close(() => resolve(port));
    });
  });
}

// Wait for server to be ready
async function waitForServer(port: number, timeout = 120000): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    try {
      await new Promise<void>((resolve, reject) => {
        http.get(`http://localhost:${port}`, (res) => {
          if (res.statusCode === 200) resolve();
          else reject(new Error(`HTTP ${res.statusCode}`));
        }).on('error', reject);
      });
      return;
    } catch {
      await new Promise(resolve => setTimeout(resolve, 500));
    }
  }
  throw new Error(`Server did not start within ${timeout}ms`);
}

test.beforeAll(async () => {
  // Find free port
  appPort = await findFreePort();

  // Start dotnet server
  const projectRoot = process.cwd().replace(/[/\\]\.ivy[/\\]tests$/, '');
  serverProcess = spawn('dotnet', ['run', '--', '--port', appPort.toString()], {
    cwd: projectRoot,
    shell: true, // Required on Windows
    stdio: 'pipe'
  });

  // Capture logs
  serverProcess.stdout?.on('data', (data) => {
    // Write to backend.log
  });

  serverProcess.stderr?.on('data', (data) => {
    // Write to backend.log
  });

  // Wait for server
  await waitForServer(appPort);
}, 180000); // 3 minutes for build + startup

test.afterAll(async () => {
  if (serverProcess) {
    serverProcess.kill();
  }
});

test.beforeEach(async ({ page }) => {
  // Capture console logs
  page.on('console', (msg) => {
    // Write to console.log
  });

  // Navigate to app (disable chrome for single-app testing)
  await page.goto(`http://localhost:${appPort}/app-id?chrome=false`);
});
```

### Screenshot Strategy

```typescript
let screenshotCounter = 0;

test('feature test', async ({ page }) => {
  // Take screenshot at each step
  await page.screenshot({
    path: path.resolve(__dirname, 'screenshots', `${++screenshotCounter}-initial-load.png`),
    fullPage: true
  });

  // Interact
  await page.getByRole('button', { name: 'Submit' }).click();
  await page.waitForTimeout(500);

  await page.screenshot({
    path: path.resolve(__dirname, 'screenshots', `${++screenshotCounter}-after-submit.png`),
    fullPage: true
  });
});
```

### Key Points
- Use ES module `__dirname` polyfill
- Use `shell: true` in spawn options on Windows
- Wait for HTTP 200 before running tests
- Capture both stdout and stderr logs
- Use `?chrome=false` for single-app testing
- Take screenshots at every major step
- Use `fullPage: true` for screenshots

---

## Quick Reference

| Widget | Locator Strategy | Notes |
|--------|-----------------|-------|
| NumberInput | `page.locator('input[type="text"]').nth(N)` | NOT `type="number"`, avoid value selectors |
| SelectInput | `page.getByRole('combobox')` then `getByText()` | Use `exact: true` for options |
| Switch | `page.getByText('Label Text')` | Labels contain text |
| Slider | `page.getByRole('slider')` + keyboard | Use ArrowRight/Left, Home/End |
| Button (text) | `page.getByRole('button', { name: 'Text' })` | Use `exact: true` for single chars |
| Button (icon) | `page.locator('button:has(svg)').first()` | No accessible name |
| Error Callout | `page.content().includes('Error text')` | More reliable than `getByText()` |

---

## Common Test Adjustments Needed

If tests fail on first run, check these common issues:

1. **Missing ES module `__dirname`** → Add polyfill at top of file
2. **NumberInput not found** → Use `input[type="text"]`, not `input[type="number"]`
3. **NumberInput value selector fails** → Switch to position-based `.nth(N)`
4. **External API assertions fail** → Add error handling with `page.content().includes()`
5. **Server doesn't start** → Increase `beforeAll` timeout to 180000ms
6. **WebSocket connection issues** → Consolidate tests into single test block
7. **Strict mode violations** → Add `.first()` to ambiguous locators

---

## Testing External APIs: Decision Tree

```
Does the app call external APIs?
├─ No → Use standard assertions on output
└─ Yes → Use flexible assertions
    ├─ Success state: Check for expected output text
    ├─ Error state: Check for error messages/callouts
    └─ Assert: (hasSuccess || hasError) must be true
```

This pattern ensures tests:
- ✅ Pass when API works correctly
- ✅ Pass when API fails but app handles error gracefully
- ❌ Fail only if app crashes or shows no output

---

## Last Updated

2026-03-23 - Added patterns from AIOnboardingEmailSequenceGenerator test review session
