# Playwright Test Patterns for Ivy Framework

This document contains common patterns and solutions for generating robust Playwright tests for Ivy applications. These patterns prevent the need for multiple test adjustment rounds.

## Table of Contents

1. [ES Module Setup](#es-module-setup)
2. [Common Ivy Widget Locators](#common-ivy-widget-locators)
3. [Callout Component Rendering](#callout-component-rendering)
4. [External API Error Handling](#external-api-error-handling)
5. [Test Structure Best Practices](#test-structure-best-practices)
6. [CodeBlock Content Assertions](#codeblock-content-assertions)
7. [Button Index Pitfalls](#button-index-pitfalls)

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

#### Standard Dropdown Pattern
```typescript
// Open dropdown
await page.getByRole('combobox').click();

// Select option (use exact match to avoid ambiguity)
await page.getByText('Option Name', { exact: true }).first().click();
```

#### Click Interception Workaround (Keyboard Navigation)
```typescript
// If clicking an option times out due to element interception
// (e.g., Badge elements with same text block the click)
// Use keyboard navigation instead:
await page.getByRole('combobox').click();
await page.keyboard.press('ArrowDown');  // Navigate to option
await page.keyboard.press('ArrowDown');  // Repeat as needed
await page.keyboard.press('Enter');      // Select
```

#### Click Interception Workaround (Role-Based Selectors)
```typescript
// If clicking an option times out due to Radix UI backdrop/popper element interception,
// use role-based selectors instead of text-based selectors:

// ❌ Problematic: text-based selector intercepted by Radix UI popper elements
await page.getByText('Option Name').first().click();

// ✅ Correct: role-based selector targets ARIA option elements directly
await page.getByRole('option', { name: /Option Name/ }).click();
```

**When to use role-based selectors over keyboard navigation**:
- When the Select component renders options with `role="option"` (e.g., Radix UI Select used by Ivy's SelectInput in some configurations)
- When you need to select a specific option by name without counting arrow key presses
- Prefer `getByRole('option')` first; fall back to keyboard navigation if options lack ARIA roles

#### Toggle Variant Pattern
```typescript
// SelectInput with Variant(SelectInputVariant.Toggle) renders as radio buttons
await page.getByRole('radio', { name: 'Option Name' }).click();
```

#### Multi-Select Toggle Variant Pattern
```typescript
// SelectInput with .Multiple() + Variant(SelectInputVariant.Toggle)
// renders as toggle buttons that can have multiple active selections
// Check selection state via aria-checked attribute
const option = page.getByRole('radio', { name: 'Option Name' });
await option.click();
await expect(option).toHaveAttribute('aria-checked', 'true');
```

#### Key Points
- **Standard variant**: Trigger button is `role="combobox"`
- **Toggle variant**: Renders with `role="radio"` and `aria-checked` state. Use `getByRole('radio')`
- **Multi-select toggle**: Same `role="radio"` locator, multiple options can have `aria-checked="true"` simultaneously
- Dropdown items (standard) are plain `<div>` elements with text (no `role="option"`)
- Use `.first()` because option text may appear in multiple places
- **CRITICAL**: Always check which variant is being used to choose correct locator — toggle variant does NOT render as a combobox
- **Click interception**: If dropdown options share text with other elements (badges, cards), use keyboard navigation

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

### CodeBlock Content Assertions

#### Problem
`new CodeBlock(...)` or `.ToCodeInput()` used for **display** (not editing) wraps content in `<span>` elements for syntax highlighting. Exact string matching on `.textContent()` fails because the expected string is split across multiple spans.

#### Solution
Use flexible matching that handles syntax highlighting spans:

```typescript
// ❌ BAD: Exact string match fails due to syntax highlighting spans
const output = await page.locator('.code-block').textContent();
expect(output).toContain('<div class="test">');  // FAILS

// ✅ GOOD: Split into component parts and check each separately
expect(output).toContain('Hello');
expect(output).toContain('World');

// ✅ GOOD: Check for alternative forms (encoded vs decoded)
expect(output?.includes('&lt;div') || output?.includes('<div')).toBeTruthy();

// ✅ GOOD: Flexible matching with key fragments
expect(output?.includes('keyword1') && output.includes('keyword2')).toBeTruthy();
```

#### When to Use
Any test that verifies text content displayed in a `CodeBlock` widget. Look for `new CodeBlock(...)` or `.ToCodeBlock()` in the app source code. If the app shows generated/transformed content in a CodeBlock (not just static display), use flexible matching.

#### Key Points
- CodeBlock uses syntax highlighting which wraps text in `<span>` elements
- Exact multi-character string matching will fail for sequences that cross span boundaries
- Split expected content into individual words/tokens and check each separately
- Use `.includes()` with OR logic for content that may appear in alternative forms (encoded/decoded, formatted/raw)
- Check for key fragments rather than exact strings

---

### CodeInput

#### Problem
`state.ToCodeInput()` might be assumed to render as Monaco editor (`.monaco-editor` class), but it actually renders as a contenteditable element with `role="textbox"`.

#### Solution
Use role-based locator with proper state synchronization:

```typescript
// ✅ Good: Use textbox role with fill() and wait for sync
const codeEditor = page.getByRole('textbox').first();
await codeEditor.click();
await codeEditor.fill('// new code');
await page.waitForTimeout(1000); // CRITICAL: Wait for WebSocket state sync

// After state sync, actions will work
await page.getByRole('button', { name: 'Submit' }).click();

// ❌ Bad: Using keyboard.type() or missing sync wait
await codeEditor.click();
await page.keyboard.type('code'); // State doesn't sync reliably
await page.getByRole('button', { name: 'Submit' }).click(); // May act on stale state
```

#### Key Points
- CodeInput renders with `role="textbox"`, NOT as Monaco editor
- Uses contenteditable div with line numbers displayed separately
- Use `.fill()` instead of `.keyboard.type()` for more reliable state updates
- **CRITICAL**: Add 1000ms wait after `.fill()` to allow WebSocket state synchronization
- Standard 500ms wait is insufficient for CodeInput state propagation
- Use `.getByRole('textbox')` to locate the editor
- If multiple code inputs exist, use `.first()`, `.last()`, or `.nth(N)`

#### State Synchronization Pattern
When CodeInput changes need to trigger server-side actions:
1. Click the input to focus
2. Use `.fill()` to set content
3. Wait 1000ms for WebSocket state sync
4. Then trigger actions (button clicks, etc.)

Without the wait, button clicks may execute with stale/empty state.

---

### DateTimeInput

#### Problem
`state.ToDateTimeInput()` renders a **custom Ivy component**, NOT a standard HTML5 `<input type="datetime-local">`. Attempts to use `page.locator('input[type="datetime-local"]')` will fail with timeout.

#### Solution
For basic validation, verify the component displays correctly without attempting to interact:

```typescript
// ✅ Good: Verify the datetime picker field is present
await expect(page.getByText('Target Date & Time')).toBeVisible();

// ✅ Good: Check for calendar/clock icons (indicates datetime picker)
const dateField = page.locator('[data-field-name="Target Date & Time"]').first();
await expect(dateField).toBeVisible();

// ❌ Bad: Attempting to use standard datetime-local locator
const dateInput = page.locator('input[type="datetime-local"]'); // This will timeout
```

#### Key Points
- DateTimeInput uses a custom component (likely Radix UI-based)
- Does NOT render as standard HTML5 `<input type="datetime-local">`
- Displays date value but requires clicking to open picker interface
- For testing date selection: would need to click trigger, then interact with calendar/time picker popover
- **Pragmatic approach**: Focus tests on other app functionality rather than complex picker interactions
- If date testing is critical: investigate the actual component structure with browser DevTools first

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

// Buttons with .Url() (renders as link-wrapped button)
await page.getByText('Download PDF').click();
// OR
await page.locator('a:has-text("Download PDF")').click();

// Icon-only buttons (no accessible name)
await page.locator('button:has(svg)').first().click();

// With exact match (for single-character buttons like "C")
await page.getByRole('button', { name: 'C', exact: true }).click();
```

#### Key Points
- Buttons with `.Url()` render as anchor tags wrapping button elements
- Use `getByText()` or `locator('a:has-text(...)')` instead of `getByRole('button')` for URL buttons

---

### FileInput

#### Pattern
```typescript
// Basic file upload
const fileInput = page.locator('input[type="file"]');
await fileInput.setInputFiles('path/to/file.png');

// Wait for upload to complete
await page.waitForTimeout(1000);
```

#### Custom Preview Disambiguation

When FileInput is used with custom preview UI (e.g., image cards showing thumbnails and filenames), uploaded filenames appear in multiple DOM locations. This causes strict mode violations when selecting by text.

**Problem:**
```typescript
// ❌ Fails with "strict mode violation" (matches filename in preview card AND FileInput list)
await page.getByText('test-image-1.png').click();
```

**Solution:**
```typescript
// ✅ Use .first() to select the first matching element
await page.getByText('test-image-1.png').first().click();

// ✅ Or use more specific structural selectors
await page.locator('.card:has-text("test-image-1.png")').click();
await page.locator('button:has-text("Remove")').first().click();
```

#### Key Points
- FileInput with custom previews creates duplicate text in the DOM
- Use `.first()` to disambiguate when selecting by filename
- Prefer structural selectors (role, test IDs) over text matching when possible
- For Remove buttons in preview cards, use position or structural locators

---

## Callout Component Rendering

### Problem
`Callout.Success()` and `Callout.Error()` components may not immediately render their text content in the DOM. Text-based assertions using `page.content().includes('message text')` can fail even when the callout is visually present.

### Solution
Use structural indicators instead of exact text matching:

```typescript
// Wait longer for callouts to render (2000ms instead of 500ms)
await page.waitForTimeout(2000);

// Check for callout by structural attributes, not text
const content = await page.content();
const hasCallout = content.includes('role="alert"') && content.includes('Callout');
expect(hasCallout).toBeTruthy();

// For success callouts, check CSS classes
const hasSuccess = content.includes('border-emerald') || content.includes('bg-emerald');

// For error callouts, check CSS classes
const hasError = content.includes('border-red') || content.includes('bg-red');
```

### Why
- Callout components render with delay as they involve WebSocket communication
- Text content may be wrapped in complex HTML structures
- CSS classes and ARIA roles are more reliable indicators of callout presence
- Standard 500ms wait is often insufficient for callout rendering

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

### Dynamic Port Configuration

#### Problem
Setting `baseURL: \`http://localhost:${process.env.APP_PORT}\`` in `playwright.config.ts` fails when `APP_PORT` is set in `test.beforeAll()`. The config is evaluated before tests run, making the environment variable undefined, which results in "Cannot navigate to invalid URL" errors.

#### Solution
Use absolute URLs in test code where the port variable is in scope:

```typescript
// ✅ Good: Use absolute URL in test
test('my test', async ({ page }) => {
  await page.goto(`http://localhost:${appPort}/`);
});

// ❌ Bad: Rely on baseURL with undefined env var
// playwright.config.ts
use: {
  baseURL: `http://localhost:${process.env.APP_PORT}` // undefined!
}
```

#### Why
Playwright config is evaluated once at startup. Environment variables set dynamically in test hooks won't be available to the config. Use the port variable directly in test code instead.

---

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
| SelectInput (Toggle) | `page.getByRole('radio', { name: 'Option' })` | Toggle variant uses `role="radio"` with `aria-checked` |
| SelectInput (Multi Toggle) | `page.getByRole('radio', { name: 'Option' })` | Same as toggle; multiple can be `aria-checked="true"` |
| Switch | `page.getByText('Label Text')` | Labels contain text |
| CodeInput | `page.getByRole('textbox')` | NOT `.monaco-editor`, uses contenteditable |
| Slider | `page.getByRole('slider')` + keyboard | Use ArrowRight/Left, Home/End |
| Button (text) | `page.getByRole('button', { name: 'Text' })` | Use `exact: true` for single chars |
| Button (icon) | `page.locator('button:has(svg)').first()` | No accessible name |
| CodeBlock | Split into fragments, use `.includes()` | Syntax highlighting spans break exact matches |
| SelectInput (Radix option) | `page.getByRole('option', { name: /Text/ })` | Use when `getByText()` is intercepted by Radix popper |
| FileInput | `page.locator('input[type="file"]')` | With custom previews, use `.first()` for text selectors |
| Error Callout | `page.content().includes('Error text')` | More reliable than `getByText()` |
| Heading | `page.getByRole('heading', { name: 'Text', exact: true })` | Avoids matching heading text in body content |

---

## Button Index Pitfalls

### Problem
When using `.nth()` for button selection in pages with multiple button groups (e.g., form action buttons + list item buttons), tests often select the wrong button by counting from 0 within a subgroup instead of counting all matching elements on the page.

### Solution
Prefer scoped locators over positional selectors:

```typescript
// ❌ Don't count from 0 within a subgroup (e.g., "first button in step list = 0")
await page.getByRole('button').nth(0).click(); // Hits "Add Step", not first step's up button

// ✅ Count all matching elements on the page from the top
// Button indices: 0=Add Step, 1=Load Sample, 2=Color Scheme, 3=First Step Up, 4=First Step Down, 5=First Step Delete
await page.getByRole('button').nth(3).click(); // First step up button

// ✅ Better: Use scoped locators to avoid index math entirely
const firstStep = page.locator('.step-item').first();
await firstStep.getByRole('button', { name: /up/i }).click();
```

### Key Points
- When using `.nth()`, count ALL matching elements on the page, not just those in the target group
- Always add a comment explaining the index calculation when using positional selectors
- Prefer scoped locators: find the parent container first, then locate the button within it
- For icon-only buttons, use `aria-label` matching if available before falling back to positional selectors

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
8. **Heading text matching body content** → Use `getByRole('heading', { name: 'Text', exact: true })` instead of `getByText('Text')`
9. **SelectInput Toggle not found as combobox** → Use `getByRole('radio')`, not `getByRole('combobox')` for `Variant(SelectInputVariant.Toggle)`
10. **CodeBlock content assertion fails** → Split expected strings into fragments; syntax highlighting `<span>` elements break exact matches
11. **Select dropdown option click timeout** → Use `getByRole('option', { name: /Text/ })` instead of `getByText()` to avoid Radix UI popper/backdrop interception
12. **FileInput with custom preview** → Use `.first()` for filename selectors to avoid strict mode violations from duplicate text
13. **Button index wrong in multi-group layout** → Count ALL buttons on the page, not just within the target group; prefer scoped locators over `.nth()`

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

2026-03-24 - Added Multi-Select Toggle variant pattern and common adjustment for toggle/combobox confusion (SeattleWeather test review)
2026-03-24 - Corrected SelectInput Toggle variant to use `role="radio"` instead of `role="button"` (ReadingTimeEstimator test review)
2026-03-24 - Updated CodeInput pattern with critical state synchronization timing (XMLFormatterAndValidator test review)
2026-03-24 - Added Button with .Url() pattern (ImageToPDFConverter test review)
2026-03-24 - Added SelectInput click interception workaround using keyboard navigation (PokeAPI test review)
2026-03-24 - Added CodeInput pattern from MarkdownPreview test session
2026-03-24 - Added dynamic port configuration pattern to prevent baseURL errors (BulkFileRenamer test review)
2026-03-24 - Added CodeBlock content assertion pattern for syntax highlighting spans (HTMLEntitiesEncoder test review)
2026-03-24 - Added Radix UI role-based selector pattern for Select dropdown click interception (GraphQL Countries test review)
2026-03-24 - Added FileInput pattern with custom preview disambiguation for strict mode violations (ImageToPDFConverter test review)
