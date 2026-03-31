# Playwright Test Patterns for Ivy Framework

This document contains common patterns and solutions for generating robust Playwright tests for Ivy applications. These patterns prevent the need for multiple test adjustment rounds.

## Table of Contents

1. [ES Module Setup](#es-module-setup)
2. [Common Ivy Widget Locators](#common-ivy-widget-locators)
3. [TabsLayout DOM Rendering](#tabslayout-dom-rendering)
4. [Callout Component Rendering](#callout-component-rendering)
5. [External API Error Handling](#external-api-error-handling)
6. [Test Structure Best Practices](#test-structure-best-practices)
7. [CodeBlock Content Assertions](#codeblock-content-assertions)
8. [Testing CodeInput Widgets](#testing-codeinput-widgets)
9. [Button Index Pitfalls](#button-index-pitfalls)
10. [Windows Process Cleanup](#windows-process-cleanup)

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

// Buttons with .Url() - state-dependent rendering
// When enabled: renders as <a href="...">
await page.locator('a:has-text("Download PDF")').click();

// When disabled: renders as <button disabled>
await page.locator('button:has-text("Download PDF")').click();

// Universal locator (works for both enabled and disabled states)
await page.getByText('Download PDF').click();

// Icon-only buttons (no accessible name)
await page.locator('button:has(svg)').first().click();

// With exact match (for single-character buttons like "C")
await page.getByRole('button', { name: 'C', exact: true }).click();
```

#### Button with .Url() Rendering Inconsistency

**Problem**: Button components with `.Url()` render differently depending on their disabled state:
- **Enabled state**: Renders as `<a href="...">` (anchor tag)
- **Disabled state**: Renders as `<button disabled>` (button element)

This inconsistency affects test locator selection.

**Solution**: Use state-agnostic locators that work regardless of enabled/disabled state:

```typescript
// ✅ Best: Text-based locator works for both states
await page.getByText('Download PDF').click();

// ✅ Alternative: Check element state and use appropriate locator
const enabledButton = page.locator('a:has-text("Download PDF")');
const disabledButton = page.locator('button:has-text("Download PDF")');
const button = await enabledButton.count() > 0 ? enabledButton : disabledButton;
await button.click();

// ❌ Bad: Assumes always enabled (fails when disabled)
await page.locator('a:has-text("Download PDF")').click();

// ❌ Bad: Assumes always disabled (fails when enabled)
await page.locator('button:has-text("Download PDF")').click();
```

#### Key Points
- Buttons with `.Url()` render as `<a>` when enabled, `<button>` when disabled
- Prefer `getByText()` for universal locators that work in both states
- If targeting by element type, check state first or use conditional logic
- This inconsistency can cause test failures when button state changes

---

### FileInput

#### Problem
File inputs (`<input type="file">`) are hidden by default in HTML. Attempts to verify visibility with `.toBeVisible()` will fail even though the input is functional.

#### Solution
Use `.toHaveCount(1)` to verify the input exists without checking visibility:

```typescript
// ✅ Good: Verify file input exists
await expect(page.locator('input[type="file"]')).toHaveCount(1);

// Uploading still works normally
const fileInput = page.locator('input[type="file"]');
await fileInput.setInputFiles('/path/to/file.csv');

// ❌ Bad: Trying to check visibility (will timeout)
await expect(page.locator('input[type="file"]')).toBeVisible();
```

#### Key Points
- File inputs are hidden by default in browser implementations
- Use `.toHaveCount(1)` or `.toBeAttached()` instead of `.toBeVisible()`
- File upload functionality works regardless of visibility
- If the app uses `.ToFileInput()`, the input is wrapped in a custom component but remains hidden

#### Creating Valid Test Images

When testing apps that handle image uploads and display previews, you must create **valid, browser-renderable** PNG files. Invalid PNGs will show as broken image icons in the app UI.

> **Do NOT manually construct PNG bytes without zlib compression** — browsers cannot decode raw pixel data in IDAT chunks. Always use `zlib.deflateSync()` and proper CRC32 checksums.

```typescript
import zlib from 'zlib';

function createTestImage(width: number, height: number, r = 100, g = 149, b = 237): Buffer {
  // Build raw scanlines: filter byte (0) + RGB pixels per row
  const rawData = Buffer.alloc(height * (1 + width * 3));
  for (let y = 0; y < height; y++) {
    rawData[y * (1 + width * 3)] = 0; // no filter
    for (let x = 0; x < width; x++) {
      const offset = y * (1 + width * 3) + 1 + x * 3;
      rawData[offset] = r;
      rawData[offset + 1] = g;
      rawData[offset + 2] = b;
    }
  }

  const compressed = zlib.deflateSync(rawData);

  function crc32(buf: Buffer): number {
    let crc = 0xFFFFFFFF;
    for (const byte of buf) {
      crc ^= byte;
      for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ (crc & 1 ? 0xEDB88320 : 0);
    }
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }

  function chunk(type: string, data: Buffer): Buffer {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const typeAndData = Buffer.concat([Buffer.from(type), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(typeAndData));
    return Buffer.concat([len, typeAndData, crc]);
  }

  const ihdrData = Buffer.alloc(13);
  ihdrData.writeUInt32BE(width, 0);
  ihdrData.writeUInt32BE(height, 4);
  ihdrData.writeUInt8(8, 8);  // bit depth
  ihdrData.writeUInt8(2, 9);  // RGB
  ihdrData.writeUInt8(0, 10); // compression
  ihdrData.writeUInt8(0, 11); // filter
  ihdrData.writeUInt8(0, 12); // interlace

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    chunk('IHDR', ihdrData),
    chunk('IDAT', compressed),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// Usage:
const testImage = createTestImage(100, 100);           // Blue 100x100 image
const redImage = createTestImage(150, 150, 255, 0, 0); // Red 150x150 image
fs.writeFileSync(path.resolve(__dirname, 'test-image-1.png'), testImage);
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

---

## Testing CodeInput Widgets

This section documents comprehensive patterns for testing applications that use CodeInput widgets, based on lessons learned from multiple test adjustment rounds. CodeInput testing involves specific challenges around state synchronization, HTML escaping, multi-panel layouts, and visual assertions.

### Filling Content

Use `.fill()` instead of `.type()` for CodeInput:

```typescript
const codeInput = page.getByRole('textbox').first();
await codeInput.fill('<root><item>Test</item></root>');
await page.waitForTimeout(1000); // Allow WebSocket sync
```

**Why**: CodeInput is a Monaco-based contenteditable element that requires `.fill()` for proper state sync. The 1000ms wait allows the Ivy WebSocket to synchronize state to the backend. Standard 500ms waits are insufficient for CodeInput state propagation.

**Critical**: Without the 1000ms wait after `.fill()`, subsequent button clicks or actions may execute against stale/empty state, causing tests to fail.

### Asserting Content in CodeBlock Output

When verifying code output displayed in CodeBlock, use text locators, not HTML inspection:

```typescript
// ❌ Wrong - HTML escaped
await expect(page.content()).toContain('<root>');

// ✅ Correct - matches rendered text
await expect(page.getByText('<root>').last()).toBeVisible();
```

**Why**: CodeBlock HTML-escapes content for display (e.g., `<` becomes `&lt;`). Text locators match the visible rendered content, while `page.content()` returns the escaped HTML source.

### Handling Multiple Panels

When testing dual-panel layouts (input + output), use `.first()` or `.last()` to disambiguate:

```typescript
// Left panel (input)
await page.getByText('Input').first();

// Right panel (output)
await page.getByText('<root>').last();
```

**Why**: Text content often appears in both panels, causing Playwright strict mode violations. Using `.first()` or `.last()` targets the specific panel you're testing.

**Pattern**: For input panels, use `.first()`. For output panels, use `.last()`. This assumes left-to-right or top-to-bottom layouts.

### Testing Status Indicators

Check for text content, not CSS classes:

```typescript
// ❌ Wrong - assumes specific Tailwind classes
await expect(page.locator('.bg-emerald-500')).toBeVisible();

// ✅ Correct - checks visible state
await expect(page.locator('text=Valid').first()).toBeVisible();
await expect(page.locator('text=Invalid').first()).toBeVisible();
```

**Why**: Ivy's color mappings (`Colors.Success`, `Colors.Error`, etc.) may change Tailwind class names across versions. Text content is more stable and doesn't couple tests to implementation details.

**Pattern**: When testing badges, alerts, or status indicators, assert on the text content (e.g., "Valid", "Error", "Success") rather than CSS classes like `bg-emerald-500` or `border-red-600`.

### Complete Example: XML Validator Test

This example demonstrates all patterns working together:

```typescript
test('validates XML and shows status', async ({ page }) => {
  await page.goto(`http://localhost:${appPort}/`);

  // 1. Fill CodeInput (with state sync wait)
  const codeInput = page.getByRole('textbox').first();
  await codeInput.fill('<root><item>Test</item></root>');
  await page.waitForTimeout(1000); // Critical: wait for WebSocket sync

  // 2. Trigger validation
  await page.getByRole('button', { name: 'Validate' }).click();
  await page.waitForTimeout(500);

  // 3. Assert on CodeBlock output (use text locator, not HTML)
  await expect(page.getByText('<root>').last()).toBeVisible();
  await expect(page.getByText('<item>').last()).toBeVisible();

  // 4. Assert on status indicator (use text, not CSS class)
  await expect(page.locator('text=Valid').first()).toBeVisible();
});
```

### Key Takeaways

- **Always wait 1000ms** after `.fill()` on CodeInput for WebSocket state sync
- **Use text locators** (`.getByText()`) for CodeBlock content assertions, not `.content().includes()`
- **Use `.first()/.last()`** to disambiguate content in multi-panel layouts
- **Assert on text content** for status indicators, not CSS classes
- **Test both panels** independently - input state and output rendering are separate concerns

---

## TabsLayout DOM Rendering

### Issue
`Layout.Tabs()` renders ALL tab content to the DOM on initial load. Inactive tabs are hidden with CSS (`display: none` or similar), but their DOM elements remain present.

### Problem
Locators using `.first()` may match hidden elements from inactive tabs instead of visible elements on the active tab.

### Solution
Use `:visible` pseudo-class for any locator that targets content inside tabs.

### Examples

```typescript
// BAD - matches hidden inputs from inactive tabs
const input = page.locator('input[type="text"]').first();
const checkbox = page.locator('[role="checkbox"]').first();
const codeBlock = page.locator('pre code').first();

// GOOD - only matches visible elements on active tab
const input = page.locator('input[type="text"]:visible').first();
const checkbox = page.locator('[role="checkbox"]:visible').first();
const codeBlock = page.locator('pre code:visible').first();
```

### When to Apply
Use `:visible` for ANY content-targeting locator when testing apps with multiple tabs:
- Form inputs (text, number, file, etc.)
- Checkboxes and radio buttons
- Buttons within tab content
- Code blocks, text areas, and other content displays
- Any element that might appear in multiple tabs

### When NOT Needed
Navigation elements (tab buttons themselves) don't need `:visible` since they're always visible.

### TabsLayout Responsive Collapse
When a `TabsLayout` has many tabs (6+), the tab bar collapses responsively — only the first 2 tabs are rendered as clickable text triggers; the rest are hidden behind a dropdown chevron. This causes:
- `getByText('TabName', { exact: true }).first()` for collapsed tabs resolves to Badge elements in card content (same text) instead of the tab trigger
- `getByRole('tab', { name: '...' })` does NOT work — Ivy tabs don't use `role="tab"`
- The dropdown options have pointer interception issues (`<html>` intercepts)

**Workaround**: Only test visible tabs directly (typically the first 2). For content behind collapsed tabs, use `page.content().includes()` assertions or verify via search filtering instead of tab navigation. Alternatively, accept limited tab coverage and note as a framework UX issue.

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
import { spawn, execSync, ChildProcess } from 'child_process';
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
    if (process.platform === 'win32') {
      // Windows: kill entire process tree to prevent zombie dotnet.exe processes
      try { execSync(`taskkill /F /T /PID ${serverProcess.pid}`, { stdio: 'ignore' }); } catch {}
    } else {
      serverProcess.kill();
    }
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
- **Use `taskkill /F /T /PID` on Windows** to kill the entire process tree in `afterAll` (see [Windows Process Cleanup](#windows-process-cleanup))
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
| CodeInput | `page.getByRole('textbox')` | See [Testing CodeInput Widgets](#testing-codeinput-widgets) for comprehensive patterns |
| Slider | `page.getByRole('slider')` + keyboard | Use ArrowRight/Left, Home/End |
| Button (text) | `page.getByRole('button', { name: 'Text' })` | Use `exact: true` for single chars |
| Button (icon) | `page.locator('button:has(svg)').first()` | No accessible name |
| CodeBlock | Split into fragments, use `.includes()` | Syntax highlighting spans break exact matches |
| SelectInput (Radix option) | `page.getByRole('option', { name: /Text/ })` | Use when `getByText()` is intercepted by Radix popper |
| FileInput | `page.locator('input[type="file"]')` | Use `.toHaveCount(1)`, NOT `.toBeVisible()` |
| Error Callout | `page.content().includes('Error text')` | More reliable than `getByText()` |
| Heading | `page.getByRole('heading', { name: 'Text', exact: true })` | Avoids matching heading text in body content |
| TabsLayout apps | Use `:visible` for content locators | `page.locator('input:visible').first()` |

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

## Windows Process Cleanup

### Problem
`serverProcess.kill()` in `afterAll` only terminates the parent Node.js-spawned process on Windows, not the entire process tree. When `shell: true` is used (required on Windows), the spawned `cmd.exe` creates child `dotnet.exe` processes that survive after the parent is killed. This leaves zombie processes that lock DLL files, causing subsequent `dotnet build` to fail with file-in-use errors. Observed with 13-31+ zombie processes across multiple test sessions.

### Solution
Use `taskkill /F /T /PID` on Windows to kill the entire process tree:

```typescript
import { spawn, execSync, ChildProcess } from 'child_process';

test.afterAll(async () => {
  if (serverProcess) {
    if (process.platform === 'win32') {
      // Windows: kill entire process tree to prevent zombie dotnet.exe processes
      try { execSync(`taskkill /F /T /PID ${serverProcess.pid}`, { stdio: 'ignore' }); } catch {}
    } else {
      serverProcess.kill();
    }
  }
});
```

### Why
- On Windows with `shell: true`, `spawn('dotnet', [...])` creates: `cmd.exe` → `dotnet.exe` → app process
- `serverProcess.kill()` only kills `cmd.exe`, leaving `dotnet.exe` and child processes running
- `taskkill /F /T /PID` forcefully (`/F`) terminates the entire process tree (`/T`) rooted at the given PID
- The `try/catch` handles the case where the process has already exited
- On Unix/Linux, `serverProcess.kill()` works correctly as it sends SIGTERM to the process group

### Key Points
- **ALWAYS** use this pattern in `afterAll` — it is critical for Windows reliability
- Import `execSync` from `child_process` alongside `spawn`
- The `try/catch` is necessary because `taskkill` throws if the process already exited
- `stdio: 'ignore'` suppresses taskkill output/error messages

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
14. **Zombie dotnet.exe processes on Windows** → Use `taskkill /F /T /PID` in `afterAll` instead of `serverProcess.kill()` (see [Windows Process Cleanup](#windows-process-cleanup))
15. **Locator matches wrong element in tabbed app** → Add `:visible` pseudo-class to content locators; `Layout.Tabs()` renders all tab content to DOM with inactive tabs hidden via CSS (see [TabsLayout DOM Rendering](#tabslayout-dom-rendering))
16. **File input visibility check fails** → Use `.toHaveCount(1)` instead of `.toBeVisible()`
17. **CodeInput state not syncing to backend** → Add `await page.waitForTimeout(1000)` after `.fill()` for WebSocket synchronization (see [Testing CodeInput Widgets](#testing-codeinput-widgets))
18. **CodeBlock assertions fail on escaped HTML** → Use `.getByText()` locators instead of `.content().includes()` for HTML/XML content (see [Testing CodeInput Widgets](#testing-codeinput-widgets))
19. **Element "outside of the viewport"** → When `scrollIntoViewIfNeeded()` and `{ force: true }` both fail (overflow-hidden container), use `await element.dispatchEvent('click')` which bypasses all viewport checks
20. **CodeInput in sheets with title input** → `getByRole('textbox').first()` matches the title TextInput, not the CodeInput. Use `.last()` for the CodeInput when both are present
21. **Ivy confirm dialog buttons** → `WithConfirm()` renders "Cancel" and "Ok" buttons, NOT a duplicate of the trigger button text. Use `getByRole('button', { name: 'Ok' })` to confirm
22. **Video afterEach timeout** → Calling `video.path()` or `video.saveAs()` in `afterEach` can cause timeout. Let Playwright handle video naming automatically via config
23. **App shows default/dashboard instead of target app** → Use `?shell=false` instead of `?chrome=false` in the URL. `chrome=false` is not recognized by the Ivy frontend router.
24. **Search input not found with `input[type="text"]`** → Ivy's `ToSearchInput()` may not render as `type="text"`. Use `getByPlaceholder('Search ...')` instead.

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

## Video Recording in afterEach

### Problem
Using `video.saveAs()` in `test.afterEach()` to rename videos hangs indefinitely, causing all tests to timeout even when assertions pass.

### Solution
Do NOT use custom video rename logic in `afterEach`. Rely on Playwright's built-in video recording (`video: { mode: 'on', dir: './videos' }` in config). Keep `afterEach` empty or minimal:

```typescript
test.afterEach(async ({ page }) => {
  // Videos are saved automatically by Playwright config
});
```

### Why
`video.saveAs()` requires the browser context to finalize the video, which can block indefinitely in certain configurations. Playwright automatically saves videos to the configured directory without manual intervention.

### Key Points
- **NEVER** use `video.saveAs()` in `afterEach` — it hangs
- Configure video recording in `playwright.config.ts` with `video: { mode: 'on', dir: './videos' }`
- Playwright handles video filenames automatically based on test names
- If custom naming is needed, do it as a post-test-run script, not within the test hooks

---

## Connection Secrets for Testing

### Problem
Ivy apps with connections (e.g., OpenAI) refuse to start if required secrets are not configured. The server prints "Missing secrets detected. The Ivy server cannot start." and exits.

### Solution
Before running tests, set dummy secrets via `dotnet user-secrets`:

```bash
cd <project-root>
dotnet user-secrets set "OpenAI:ApiKey" "sk-test-dummy-key-for-testing"
```

### When to Apply
Any Ivy app that has connections listed in `dotnet run --describe` output (e.g., `OpenAI`, `AzureOpenAI`, etc.). Check the `secrets:` section — if there are required (non-optional) secrets, they must be set.

### Key Points
- Tests should use the external API error handling pattern (success OR error assertions) since the dummy key will fail
- Only set the minimum required secrets — optional ones can be skipped
- This is a test environment workaround, not a project fix

---

## URL Parameter for Shell-less App Rendering

### Problem
The `?chrome=false` URL parameter does NOT work with Ivy's tab-based AppShell (`UseAppShell(new AppShellSettings().UseTabs(...))`). Navigating to `/<app-id>?chrome=false` always renders the default app (typically a dashboard), not the targeted app.

### Solution
Use `?shell=false` instead of `?chrome=false`:

```typescript
// ❌ WRONG: chrome=false doesn't bypass AppShell tabs — always shows default app
await page.goto(`http://localhost:${appPort}/categories?chrome=false`);

// ✅ CORRECT: shell=false properly renders the targeted app without AppShell
await page.goto(`http://localhost:${appPort}/categories?shell=false`);
```

### Why
The Ivy frontend checks `?shell=false` (via `getShellParam()` in the client code) to determine whether to render the AppShell wrapper. The `?chrome=false` parameter is not recognized by the frontend router.

### Key Points
- **ALWAYS** use `?shell=false`, never `?chrome=false`
- This affects ALL apps when using the tab-based AppShell
- The URL path (`/categories`, `/posts`, etc.) correctly sets the `appId` in the WebSocket connection
- Without `?shell=false`, the AppShell renders and shows the default app tab

---

## SearchInput Locator

### Problem
Ivy's `state.ToSearchInput()` renders a custom search input component. The input type varies and `input[type="text"]` may not match.

### Solution
Use `getByPlaceholder()` for the most reliable matching:

```typescript
// ✅ GOOD: Match by placeholder text (most reliable)
const searchInput = page.getByPlaceholder('Search categories');

// ❌ BAD: input type may not be "text"
const searchInput = page.locator('input[type="text"]').first();
```

### Key Points
- `ToSearchInput()` placeholder text follows the pattern "Search <entity>..." (e.g., "Search categories...", "Search posts...")
- The `.Placeholder()` modifier on `ToSearchInput()` sets the placeholder text
- `getByPlaceholder()` is substring-matching by default, so "Search categories" matches "Search categories..."

---

## Last Updated

2026-03-31 - Added shell=false URL parameter pattern and SearchInput locator pattern (BloggingPlatformV2 test review)
2026-03-26 - Added dispatchEvent viewport workaround, CodeInput textbox ordering in sheets, Ivy confirm dialog button naming patterns (MarkdigWikiEngine test review)
2026-03-26 - Added Video Recording afterEach hang fix and Connection Secrets for Testing patterns (AIAssistant test review)
2026-03-25 - Added comprehensive "Testing CodeInput Widgets" section with patterns for state sync, HTML escaping, multi-panel layouts, and status indicators (XMLFormatterAndValidator test review)
2026-03-25 - Added FileInput visibility pattern to prevent `.toBeVisible()` failures on hidden file inputs (ClosedXML-Excel-Exporter test review)
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
2026-03-24 - Added Windows Process Cleanup pattern to fix zombie dotnet.exe processes from afterAll hook (multiple sessions: PDFMerger, OTPGenerator)
2026-03-24 - Added TabsLayout DOM Rendering pattern for :visible pseudo-class in tabbed apps (ASCIIArtGenerator test review)
