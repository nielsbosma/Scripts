# Ivy Playwright Test Knowledge Base

This file is automatically updated by IvyGenerateTests.ps1 after each successful run.
Claude reads this before generating tests, so accumulated learnings improve future test generation.

---

## Ivy Framework Basics

- Ivy apps are .NET web apps started with `dotnet run -- --port <port>`
- The server prints `Ivy is running on http://localhost:<port>` when ready
- Apps are decorated with `[App(icon: Icons.X, path: ["Apps"])]` and inherit `ViewBase`
- The `Build()` method returns the UI tree
- State is managed via `UseState<T>()` which returns reactive state objects
- Services are injected via `UseService<T>()`

## Ivy UI Components

- `Layout.Center()`, `Layout.Vertical()`, `Layout.Horizontal()` — layout containers
- `Text.H2()`, `Text.P()`, `Text.Label()`, `Text.InlineCode()` — text elements
- `Slider` — range input, configured with `.Min()`, `.Max()`, `.Step()`
- `Switch` — toggle input, configured with `.Label()`
- `Button` — click handler, configured with `.Icon()`, `.Variant()`, `.Disabled()`
- `Badge` — status label with variant (Destructive, Warning, Success, Info, Secondary)
- `Card` — container card component
- `Toast` — notification via `IClientProvider.Toast(message, type)`
- State bindings: `state.ToSliderInput()`, `state.ToSwitchInput()`

## Playwright Test Patterns for Ivy

### Project Setup
- Tests live in `.ivy/tests/` within the Ivy project
- Use `package.json` with `@playwright/test` dependency
- `playwright.config.ts` targets Chromium only, single worker, no retries
- Config uses `process.env.APP_PORT` for base URL

### App Lifecycle in Tests
- `beforeAll`: find free port via `net.createServer()`, spawn `dotnet run -- --port <port>`, wait for HTTP 200
- `afterAll`: kill the spawned process
- `beforeEach`: navigate to `http://localhost:<port>`
- Use `cwd: process.cwd().replace(/[/\\]\.ivy[/\\]tests$/, "")` to resolve project root from test dir
- Wait for server with polling loop (500ms interval, 30s timeout)

### Locator Strategies
- Prefer `page.getByText()` for visible text content
- Use `page.getByRole("button", { name: /pattern/i })` for buttons
- Use `page.locator("code")` for inline code elements
- Use `.first()` when multiple matches are possible
- Use `waitFor({ state: "visible", timeout: 5000 })` for async content

### Common Test Categories
1. **Visibility tests** — verify UI elements render correctly
2. **Interaction tests** — click buttons, toggle switches, move sliders
3. **State change tests** — verify UI updates after interactions
4. **Output validation** — check generated/computed values appear correctly

### Gotchas & Tips
- Ivy apps may take a few seconds to start; 30s timeout is safe
- Use `shell: true` in spawn options on Windows
- Password/random generation tests: compare two outputs rather than asserting exact values
- Switch/toggle labels include the label text, use `getByText()` to find them
- After clicking a button, use `waitForTimeout(500)` or `waitFor()` before asserting changes
- Badges with strength/status text may appear multiple times; use `.first()`

---

## Run History

<!-- Entries are appended automatically after each successful test generation -->

### 2026-03-09 20:46 — Parsely.Markflow
- CodeMirror-based code inputs (from `state.ToCodeInput()`) use `.cm-content[contenteditable='true']` as the editable locator; type into them via `click()` then `page.keyboard.type()` rather than `.fill()`
- For CodeMirror inputs, the second editor (read-only/disabled output) is accessed via `.cm-content` with `.nth(1)` index selector
- Markdig's `ToHtml` with `UseAdvancedExtensions()` generates heading IDs like `id="hello-world"` ÔÇö useful for asserting exact HTML output in tests
- `Button.Disabled()` with a reactive condition (e.g., `string.IsNullOrWhiteSpace(html.Value)`) correctly toggles the HTML `disabled` attribute, testable via `toBeDisabled()`/`toBeEnabled()`
- Multi-line input in CodeMirror requires line-by-line `keyboard.type()` + `keyboard.press("Enter")` rather than pasting a single string with newlines
- `Button.Variant(ButtonVariant.Ghost)` and `.Primary()` render as standard `role="button"` elements ÔÇö no special locator strategy needed
- After Clear button resets state, a `waitForTimeout(1000)` is needed before asserting the UI has updated (disabled state, empty fields)


### 2026-03-09 21:01 — Chromatica.Palettes2
- `Layout.TopCenter()` serves as a top-aligned centered layout container; the app renders without needing explicit navigation to a sub-path (loads at root `/`)
- `state.ToTextInput()` renders as a standard `role="textbox"` element, locatable via `page.getByRole("textbox")` and compatible with `.fill()` for input
- `.Placeholder()` on text inputs sets the HTML placeholder attribute; tests can verify presence but the successful tests used `.fill()` rather than asserting placeholder text
- `.Primary()` and `.Outline()` button variants both render as standard `role="button"` elements with no special locator handling needed; `.Disabled()` with reactive boolean correctly toggles the HTML `disabled` attribute
- Suggested prompt buttons that both set state and trigger an async action (e.g., `prompt.Set("..."); await GeneratePalette()`) populate the input with lowercase text ÔÇö assert `.toHaveValue("luxury spa")` not `"Luxury spa"`
- For API-dependent tests, use `Promise.race()` with both success and error element waiters (30s timeout) to handle cases where API keys may not be configured ÔÇö test passes regardless of API availability
- `Callout.Error()` renders error text that can be located via `page.getByText(/Failed to generate/i)` ÔÇö no special selector needed for Ivy callout components
- `new Progress().Goal()` renders a loading indicator; combined with text elements, the loading state is brief and may require immediate screenshot capture after click

