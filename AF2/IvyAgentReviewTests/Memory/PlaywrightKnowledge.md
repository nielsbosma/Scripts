# Ivy Playwright Test Knowledge Base

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
- `state.ToSelectInput().Variant(SelectInputVariants.Toggle)` renders as radio buttons — use `getByRole("radio", { name: "OptionName" })` to click them, NOT `getByText()` (the option text may appear in headings/descriptions too)
- `IClientProvider.Toast()` renders both a visible `<div>` and an `aria-live` status `<span>` — use `getByText("message", { exact: true })` to avoid strict mode violations
- `state.ToTextareaInput()` renders as a standard `<textarea>` element, locatable via `page.locator("textarea").first()`; disabled output textarea is the `.nth(1)`
- Clipboard `writeText` fails in headless Chromium with "Write permission denied" — this is expected and not an app bug
- `state.ToSliderInput()` renders as a Radix UI slider with `role="slider"`, NOT a native `<input type="range">` — use `page.getByRole("slider")` and keyboard interaction (ArrowRight/ArrowLeft to increment/decrement by step, Home/End for min/max)
- `UseChrome()` renders a hidden sidebar search `<input type="search" data-testid="sidebar-search">` that is the first `input` in the DOM but outside the viewport — `page.locator("input").first()` will target it instead of app inputs. Use `input[type='text']` or label-based locators to target app inputs
- **Single-app Chrome auto-selection**: When `UseChrome().UseTabs()` is enabled and there's only ONE app registered, Chrome automatically opens that app's tab on page load — no need to click the sidebar nav item. Clicking it may cause a re-navigation that times out.
- **Sidebar nav button name conflicts**: Chrome sidebar renders app names as `role="button"` elements. A button with text "C" will conflict with "Calculator" sidebar button when using `getByRole("button", { name: "C" })` — always use `{ exact: true }` for single-character button names
- **`waitForServer` must use `http` module**, not `fetch` — `fetch` may not be available in all Node.js versions used by Playwright. Use `http.get()` with polling loop instead
- `state.ToBoolInput().Variant(BoolInputVariants.Checkbox)` renders as `<button role="checkbox">` (Radix UI), NOT a native `<input type="checkbox">` — `getByRole("checkbox", { name: /.../ })` and `getByLabel()` do NOT work for locating these; use `page.locator('[role="checkbox"]').nth(N)` by index order instead
- `new Card(content, header: Text.H3("Title"))` — the card header text (e.g., "Monthly Revenue") will match `getByText()` along with any content containing the same substring (e.g., "Total Monthly Revenue:"), causing strict mode violations. Always use `getByRole("heading", { name: "Title" })` for card headers
- `new Card(content).Title("X")` — Card `.Title()` does NOT render as an HTML heading element (`<h1>`-`<h6>`), so `getByRole("heading", { name: "X" })` will fail. Use `getByText("X", { exact: true }).first()` instead. Only explicit `Text.H2()`/`Text.H3()` passed as card header render as headings.
- `state.ToMoneyInput().Currency("USD").Precision(0)` renders as a text input with formatted currency (e.g., "$850,000") — values are displayed with `$` prefix and comma separators
- `.ToDetails()` on an anonymous object renders key-value pairs with PascalCase property names converted to spaced labels (e.g., `MonthlyNetBurn` → "Monthly Net Burn")

## Critical: ValueTuple Crash Pattern

- **NEVER** use C# ValueTuple syntax `Layout.Vertical() | (item1, item2, ...)` when the tuple contains widgets — `DefaultContentBuilder.Format()` calls `ValueTuple.ToString()` which triggers `PrintMembers()` → `get_Id()` on uninitialized widgets, causing `InvalidOperationException`
- **Always** use `|` operator chaining instead: `Layout.Vertical() | item1 | item2 | item3`
- This is a Framework bug in `DefaultContentBuilder.Format()` (line 171) — note as external issue for planning
- Affects ALL widget types (Field, TextInput, Button, etc.) when placed in tuples

## Test Structure Patterns

- `test.beforeAll` runs once per `test.describe` block. Multiple `test.describe` blocks = multiple `beforeAll` executions = multiple server spawns and potential DLL lock conflicts.
- For shared server: put all tests in one `test.describe`, or use top-level `test()` calls outside describe blocks which share the file-level `beforeAll`.
- Always kill app processes after test runs on Windows — lingering processes lock DLLs and prevent rebuild on next run. Use `powershell.exe -NoProfile -Command 'Get-Process -Name "AppName" -ErrorAction SilentlyContinue | Stop-Process -Force'`
- When stale processes lock DLLs and `dotnet run` fails repeatedly, spawn the pre-built exe directly: `spawn(path.join(projectRoot, "bin", "Debug", "net10.0", "AppName.exe"), ["--port", port], ...)`
- Screenshot/log path resolution: use `path.resolve(__dirname)` in spec files, NOT `process.cwd()` — Playwright may resolve cwd differently than expected, causing silent file write failures
- Clicking `ListItem` in Ivy lists: extract the visible item title text from the page (e.g., via regex on body text) and use `getByText(name, { exact: true }).dispatchEvent("click")`. Filtering parent divs by `hasText` matches too many ancestors
- `page.goBack()` in Ivy SPA may not reliably restore blade state — prefer re-navigating or keeping blade context

## Ivy App Construction

- Ivy apps MUST have a parameterless constructor — `AppDescriptor.CreateApp()` uses `Activator.CreateInstance` without DI
- Do NOT use primary constructor injection like `MyApp(IClientProvider client) : ViewBase` — causes `MissingMethodException` at runtime
- Instead, use `var client = UseService<IClientProvider>()` inside the `Build()` method

## Card Component

- `new Card(content).Title("X")` renders the title as a `<span>`, NOT as a heading element — use `getByText("X", { exact: true })` to locate card titles, not `getByRole("heading")`
- Card title text can cause strict mode violations if the same substring appears elsewhere — always use `{ exact: true }`
- Note: `new Card(content, header: Text.H3("X"))` renders a heading (see Skyline entry), but `.Title("X")` does not

## Ivy Component Test Patterns

- `AsQueryable().ToDataTable()` renders using glide-data-grid — a virtualized grid where cells have `role="gridcell"` but may not be "visible" (outside virtual viewport). Use `toBeAttached()` instead of `toBeVisible()` for these cells.
- `state.ToNumberInput().Variant(NumberInputVariants.Slider)` renders similarly to `ToSliderInput()` — a Radix slider with `role="slider"`.
- `state.ToSelectInput(options).Variant(SelectInputVariants.Toggle)` with string arrays renders radio buttons — use `getByRole("radio", { name: "OptionName" })`.
- `state.ToSelectInput([new Option<T>("Label", Value), ...])` (without Toggle variant) renders as a dropdown with `role="combobox"` — click to open, then `getByRole("option", { name: "Label" }).click()` to select
- `.ToTable()` on anonymous object collections renders as a standard HTML `<table>` — buttons in table cells are locatable via `page.locator("table button")`

## DateInput (ToDateInput) Calendar Popover

- `state.ToDateInput()` renders as a `<button data-slot="calendar">` trigger that opens a Radix Popover with a react-day-picker Calendar
- It is NOT a native `<input type="date">` — do NOT use `input[type="date"]` selectors
- The trigger button shows the formatted date or placeholder text, with a CalendarIcon
- **Calendar navigation**: The calendar caption has a `MonthYearInput` component with two `<input>` fields:
  - Month input: `input[placeholder="M"]` (width w-6)
  - Year input: `input[placeholder="YYYY"]` (width w-10)
  - Fill month number and year, press Enter to navigate to that month/year
- **Day selection**: Day buttons are inside `div[data-slot="calendar"]` (the calendar root, NOT the trigger button). Use `page.locator('div[data-slot="calendar"]').locator("button").filter({ hasText: /^15$/ }).first().click()`
- The popover content renders via Radix Portal at document root — selectors like `input[placeholder="M"]` work globally
- The calendar trigger button selector: `page.locator('button[data-slot="calendar"]').first()`
- After selecting a day, the popover auto-closes and the trigger button shows the formatted date
- `nullable` dates show a clear (X) button when a value is set

- `state.ToSelectInput(options)` WITHOUT `.Variant(SelectInputVariants.Toggle)` renders as a Radix dropdown (not native `<select>`) — click the trigger text to open, then `getByText("Option", { exact: true }).first().click()` to select.
- `page.goto()` with `waitUntil: "networkidle"` hangs on Ivy apps because WebSocket connections keep the network active — use `waitUntil: "domcontentloaded"` instead.
- `UseChrome().UseTabs(preventDuplicates: true)` with a single app auto-opens the tab — no sidebar click needed for navigation.

## Run History

### 2026-03-10 — Tempus.AgeCalc
- `state.ToDateInput()` renders as a `<button data-slot="calendar">` popover trigger, NOT a native date input
- Calendar month/year navigation via `input[placeholder="M"]` and `input[placeholder="YYYY"]` + Enter
- Day buttons inside `div[data-slot="calendar"]` (calendar root) — filter by exact day number regex
- `Card.Title("X")` does NOT render as a heading — `getByRole("heading")` fails; use `getByText("X").last()` to skip sidebar/tab matches
- `getByText("Birthdate")` matched 3 elements (label, placeholder "Select your birthdate", message "Enter your birthdate...") — use `{ exact: true }`

### 2026-03-10 — ReversiForge.AI
- Single-app Chrome tabs with `preventDuplicates: true` auto-opens the app — no sidebar navigation needed
- `page.goto` with `waitUntil: "networkidle"` hangs indefinitely on Ivy apps (WebSocket keeps network active) — always use `"domcontentloaded"`
- `ToSelectInput(enumOptions)` without `.Variant(Toggle)` renders as Radix dropdown, not native `<select>` or radio buttons
- `ToBoolInput()` checkbox buttons: clicking label text still does NOT toggle — must click `[role="checkbox"]` button directly (confirmed again)
- Grid of buttons with `Layout.Grid().Columns(8)` renders fine — empty ghost buttons are invisible (no background/border), only occupied cells visible

### 2026-03-10 — Polyglot.TypeTrainer
- `new Html(...)` component renders raw HTML content but it appears invisible — the word display area is completely blank in all screenshots. Likely renders in an iframe without CSS custom property inheritance (`var(--foreground)` etc. resolve to nothing). Hardcoded colors or native Ivy components would fix this.
- `SelectInput` with options that share a prefix (e.g., "Deutsch" and "Deutsch (Schweiz)", or "5 seconds" and "15 seconds") cause strict mode violations — always use `{ exact: true }` with `getByText()`
- `TextInput` onChange fires with the full new value, not character-by-character — `fill("test")` sends value "test" in one event. The timer start condition `e.Value.Length == 1 && userInput.Value.Length == 0` only triggers with single-char input, so use `keyboard.type("t")` not `fill("t")` for reliability
- `UseEffect` with `async` lambda containing `while(true) + Task.Delay(1000)` works as a polling timer in Ivy

### 2026-03-10 — CineStream.Converter
- `AsQueryable().ToDataTable()` uses glide-data-grid (virtualized) — cells are `role="gridcell"` but may not pass `toBeVisible()` check; use `toBeAttached()` instead
- DataTable with `.Config(c => { c.AllowFiltering = true; c.ShowSearch = true; })` shows filter icon button and search — but these may be above/below the grid viewport
- `state.ToNumberInput().Variant(NumberInputVariants.Slider)` renders as Radix slider, same as `ToSliderInput()`
- Multiple `test.describe` blocks in one file each trigger their own `beforeAll` — caused server re-spawn failure due to DLL locks from first server instance
- Solution: use top-level `test()` (outside `describe`) for tests that need to share the same server lifecycle

### 2026-03-09 20:46 — Parsely.Markflow
- CodeMirror-based code inputs (from `state.ToCodeInput()`) use `.cm-content[contenteditable='true']` as the editable locator; type into them via `click()` then `page.keyboard.type()` rather than `.fill()`
- For CodeMirror inputs, the second editor (read-only/disabled output) is accessed via `.cm-content` with `.nth(1)` index selector
- Markdig's `ToHtml` with `UseAdvancedExtensions()` generates heading IDs like `id="hello-world"` — useful for asserting exact HTML output in tests
- `Button.Disabled()` with a reactive condition correctly toggles the HTML `disabled` attribute, testable via `toBeDisabled()`/`toBeEnabled()`
- Multi-line input in CodeMirror requires line-by-line `keyboard.type()` + `keyboard.press("Enter")` rather than pasting a single string with newlines
- `Button.Variant(ButtonVariant.Ghost)` and `.Primary()` render as standard `role="button"` elements — no special locator strategy needed
- After Clear button resets state, a `waitForTimeout(1000)` is needed before asserting the UI has updated

### 2026-03-10 — ByteForge.UrlCraft
- `state.ToSelectInput().Variant(SelectInputVariants.Toggle)` renders enum options as radio buttons with `role="radio"` and `aria-label` matching the enum value name
- Toast messages from `client.Toast()` produce duplicate text nodes (visible div + aria-live span) — always use `{ exact: true }` with `getByText` for toast assertions
- `state.ToTextareaInput()` renders as `<textarea>`, output via `new TextInput().Variant(TextInputVariants.Textarea).Disabled()` also renders as `<textarea>` — use `.first()` / `.nth(1)` to distinguish

### 2026-03-10 — Nexus.PasswordForge2
- `state.ToSliderInput()` renders Radix slider (`role="slider"`), not native range input — interact via keyboard: `focus()` then `ArrowRight`/`ArrowLeft` (step by 1), `Home`/`End` for min/max
- `state.ToBoolInput().Variant(BoolInputVariants.Checkbox)` renders `<button role="checkbox">` but `getByRole("checkbox", { name })` and `getByLabel()` fail to locate them — the label `<label for="id">` association doesn't work for Playwright's accessible name resolution; use `page.locator('[role="checkbox"]').nth(N)` by DOM order
- Clicking the checkbox label text via `getByText("Label").click()` also does NOT toggle the checkbox — must click the `<button>` element directly
- `Progress` component with dynamic color shows correctly as a colored progress bar

### 2026-03-10 — Skyline.RunwayCalculator
- `new Card(content, header: Text.H3("X"))` card headers cause strict mode violations with `getByText("X")` when page also contains "Total X:" text — use `getByRole("heading", { name: "X" })` instead
- `state.ToMoneyInput()` renders formatted currency inputs (e.g., "$850,000") — values visible as text with `$` and commas
- `.ToDetails()` converts anonymous object properties to readable labels (PascalCase → spaced) and displays as key-value pairs
- Stale dotnet processes from previous test runs can lock DLLs and prevent rebuilds — kill processes between runs; `taskkill /f` may fail, use `wmic process where "name='X.exe'" delete` as fallback

### 2026-03-09 21:01 — Chromatica.Palettes2
- `Layout.TopCenter()` serves as a top-aligned centered layout container; the app renders at root `/`
- `state.ToTextInput()` renders as a standard `role="textbox"` element, locatable via `page.getByRole("textbox")` and compatible with `.fill()`
- `.Primary()` and `.Outline()` button variants both render as standard `role="button"` elements; `.Disabled()` with reactive boolean correctly toggles HTML `disabled` attribute
- Suggested prompt buttons that both set state and trigger an async action populate the input with lowercase text — assert `.toHaveValue("luxury spa")` not `"Luxury spa"`
- For API-dependent tests, use `Promise.race()` with both success and error element waiters (30s timeout) to handle cases where API keys may not be configured
- `Callout.Error()` renders error text locatable via `page.getByText(/Failed to generate/i)` — no special selector needed
- `new Progress().Goal()` renders a loading indicator; the loading state is brief and may require immediate screenshot capture after click

### 2026-03-10 — Numerix.Statistics
- ValueTuple syntax in `Build()` crashes with `InvalidOperationException: uninitialized WidgetBase Id` — switched to `|` operator chaining
- `.WithField().Label("Numbers")` on textarea also crashes in tuple context — replaced with separate `Text.Label("Numbers")`
- `.ToDetails()` on anonymous object renders clean key-value pair table in a card
- Spawning pre-built exe (`bin/Debug/net10.0/AppName.exe`) avoids `dotnet run` rebuild DLL lock issues
- `Text.Label()` works as a standalone label element outside of `.WithField()`

### 2026-03-10 — Ivy.TextAnnotate (Widget Library)
- Widget library projects have `.samples/` subfolder with the runnable app — tests must use `samplesDir` not `projectRoot` for `dotnet run`
- `[ExternalWidget]` components show "Unknown component type: Namespace.WidgetName" when the embedded JS bundle isn't served to the browser — this is a Framework issue, not a test issue
- Ivy NuGet 1.2.17 is missing `Layout`, `Text`, `ButtonVariant`, `ChromeSettings`, `Server.UseCulture()` — these APIs only exist in source. Use `ProjectReference` to Ivy source if samples require them.
- Generated sample code may use stale API patterns: `Button.Style()` → `.Variant()`, `ButtonStyle` → `ButtonVariant`, `HandleClick` → `.OnClick()`, `HandleChange(state.Set)` → `HandleChange(v => state.Set(v))` (Set returns T, not void)
- Without `UseChrome()`, Ivy SPA doesn't support URL-based app routing — `/app-name` shows the default app. Must enable Chrome for multi-app navigation.
- `powershell -Command "Get-Process -Name 'X' -ErrorAction SilentlyContinue | Stop-Process -Force"` is more reliable than `taskkill /f /im` for killing stale processes on Windows

### 2026-03-10 — Calc.Desktop
- Single-app Chrome auto-opens the only app — clicking sidebar nav item is unnecessary and can cause timeout
- `getByRole("button", { name: "C" })` conflicts with "Calculator" sidebar button — use `{ exact: true }` for short button names
- `Layout.Grid().Columns(4).Gap(4).Width(Size.Units(280))` renders buttons with excessive horizontal spacing — grid cells expand to fill container width
- `GridRowSpan(2)` on a button doesn't produce a visually distinct two-row button in the rendered output
- `http.get()` is more reliable than `fetch()` for server health checks in Playwright test setup

### 2026-03-10 — Nexus.DecisionMatrix
- Card `.Title("X")` does NOT render as HTML heading — `getByRole("heading")` fails; use `getByText("X", { exact: true }).first()` instead
- Badge `.OnClick()` works for removable items — clicking badge text triggers the click handler
- `NumberInput<int>` renders as a standard text input with `placeholder` attribute — locatable via `input[placeholder="1-10"]`
- `.ToNumberInput()` on state renders similarly with placeholder support
- App had no runtime errors — clean first run, only test locator fixes needed

### 2026-03-10 — Nexus.HumanCore
- **Chrome tabs start with NO tab open** — `UseChrome(new ChromeSettings().UseTabs())` renders a sidebar but the content area is blank on initial load. Tests MUST click a sidebar item (e.g., `page.getByText("Dashboard").first().click()`) before asserting content
- Navigation is via sidebar nav items, NOT `role="tab"` — use `page.getByText("AppName").first().click()`. **BUT** sidebar items may be outside the viewport in headless mode — `click()` and `click({ force: true })` both fail with "Element is outside of the viewport". Use `dispatchEvent("click")` instead, or use sidebar search first to filter then `dispatchEvent("click")`
- `Icons.Plus.ToButton().Ghost().Tooltip("Create X").ToTrigger(...)` — the tooltip text does NOT become the button's accessible name in Playwright. `getByRole("button", { name: /Create X/i })` fails. Use `page.locator("button").filter({ has: page.locator("svg") }).first()` instead
- Ivy `ListItem` does not have a `data-ivy-list-item` attribute — fallback selectors are needed to click list items in tests
- CRUD apps with `UseBlades()` pattern: list blade on left, detail blade opens on right when item clicked — the blade push/pop pattern
- `MetricView` renders as cards with title, icon, value, and trend percentage — fully functional with seeded data
- Chart views (LineChart, PieChart, BarChart, AreaChart) wrapped in Card with Skeleton loading — charts may be empty for short date ranges with no matching data
- `HeaderLayout(header, body)` pattern used for Dashboard — header contains the date range toggle, body contains the content
- Lists sorted alphabetically may push expected items below viewport — assert items visible at the TOP of the sorted list, not arbitrary ones

### 2026-03-10 — Nexus.CrmPortal
- Complex CRUD app with 4 apps (Dashboard, Contacts, Deals, Activities), Chrome sidebar + tabs, blade navigation, SQLite EF Core
- All 15 tests passed after 1 fix round (test assertion corrections only, no project fixes needed)
- **List sort order matters**: `UseQuery` with `OrderByDescending(e => e.CreatedAt)` means newest items appear first — don't assume alphabetical sort when asserting visible list items
- `Icons.Plus.ToButton().Ghost().Tooltip("Create X").ToTrigger(...)` — tooltip text does NOT become accessible name; use `page.locator("button").filter({ has: page.locator("svg") }).first()` (confirmed from HumanCore)
- Backend parsing error `Must specify valid information for parsing in the string` appeared once — non-crashing, likely null value in metric calculation
- `SelectInput` with async options (entity dropdowns in create/edit forms) works — opens dialog/sheet with form fields
- Chrome sidebar with multiple apps starts blank — must click sidebar item to open app tab

### 2026-03-10 — Clockwise.MeetingCost
- Primary constructor injection `MyApp(IClientProvider client)` crashes with `MissingMethodException` — Ivy uses `Activator.CreateInstance` (parameterless). Fix: use `UseService<IClientProvider>()` in `Build()`
- Card `.Title("X")` renders `<span>` not heading — use `getByText("X", { exact: true })`, confirmed same as Nexus.DecisionMatrix finding
- `ToSelectInput([new Option<T>()])` (no Toggle variant) renders `role="combobox"` dropdown — open with click, select via `getByRole("option", { name })`
- `.ToTable()` renders standard HTML `<table>` with buttons in cells locatable via `page.locator("table button")`
- `UseEffect` with `System.Threading.Timer` works for real-time updates (1-second polling)

### 2026-03-10 — PawByte.Tamadog
- Simple single-app project with Chrome tabs — clean pass, no runtime errors, no project fixes needed
- Sidebar search + `dispatchEvent("click")` pattern works reliably for navigating to apps in Chrome tabs mode when items are outside viewport
- `Progress` component with `.Color()` renders correctly for stat bars
- `UseEffect` with `System.Threading.Timer` works for periodic stat decay — no issues observed

### 2026-03-10 — HoofTrack.StableVault
- CRUD app with `UseBlades()` and Chrome tabs — clean pass, no runtime errors, no project fixes needed
- `Card.Title("Horse Details")` renders as text, NOT `role="heading"` — use `getByText()` not `getByRole("heading")`
- `ListItem` click by parent div `filter({ hasText })` fails — matches too many ancestors. Must extract specific title text and use `getByText(name, { exact: true }).dispatchEvent("click")`
- Screenshot path must use `path.resolve(__dirname)` not `process.cwd()` — the latter silently fails to write files in Playwright context
- `safeClick` pattern: try `.click({ timeout: 3000 })`, catch and fall back to `.dispatchEvent("click")` — handles both in-viewport and out-of-viewport elements
- `page.goBack()` after blade push doesn't restore previous blade — SPA routing doesn't map 1:1 to browser history for blade navigation
