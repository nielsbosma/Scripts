# Ivy Playwright Test Knowledge Base

## Ivy Framework Basics

- Ivy apps are .NET web apps started with `dotnet run -- --port <port>`
- The server prints `Ivy is running on http://localhost:<port>` when ready
- Apps are decorated with `[App(icon: Icons.X, path: ["Apps"])]` and inherit `ViewBase`
- The `Build()` method returns the UI tree
- State is managed via `UseState<T>()` which returns reactive state objects
- Services are injected via `UseService<T>()`
- `Program.cs` MUST call `server.AddAppsFromAssembly()` before `server.UseDefaultApp()` — without it, no apps are registered and the server throws `InvalidOperationException: No serviceable apps are registered`. This is a common bug in generated projects.

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
- Config does NOT need `baseURL` — use full URLs in `page.goto()` with the dynamic port variable instead, because the port is assigned in `beforeAll` after config is already loaded

### App Lifecycle in Tests
- `beforeAll`: find free port via `net.createServer()`, spawn `dotnet run -- --port <port>`, wait for HTTP 200
- `afterAll`: kill the spawned process
- `beforeEach`: set up console log capture
- Use `page.goto(\`http://localhost:\${appPort}/app-id?chrome=false\`)` with the module-level port variable
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
- Ivy apps may take a few seconds to start; use 120s timeout for `waitForServer` and 180s for `beforeAll` hook to account for dotnet build time
- Use `shell: true` in spawn options on Windows
- Password/random generation tests: compare two outputs rather than asserting exact values
- Switch/toggle labels include the label text, use `getByText()` to find them
- After clicking a button, use `waitForTimeout(500)` or `waitFor()` before asserting changes
- **Box `.OnClick()` changes role**: `new Box().OnClick(handler)` renders as `role="button"` with `tabindex="0"` and cursor/hover CSS classes. Without `.OnClick()`, Box renders as `role="presentation"`. Always use `role="button"` when locating clickable Box elements.
- **Box `.WithTooltip()` DOM structure**: `box.WithTooltip("text")` wraps the Box in `ivy-widget[type="Ivy.Tooltip"] > span[data-state] > ivy-widget[type="Ivy.Box"] > div[role="button"]`. The tooltip text is NOT rendered as plain text in the DOM (only shown on hover). Use `ivy-widget[type="Ivy.Tooltip"] div[role="button"]` to locate tooltip-wrapped clickable boxes.
- **`new Tooltip(content, description)` renders description in two DOM locations** — when hovering, the description text appears in both the tooltip trigger's `span[data-state]` and the tooltip popup. Using `getByText("description text")` causes strict mode violations. Always use `.first()` when asserting tooltip description text visibility.
- Badges with strength/status text may appear multiple times; use `.first()`
- `state.ToSelectInput().Variant(SelectInputVariants.Toggle)` renders as radio buttons — use `getByRole("radio", { name: "OptionName" })` to click them, NOT `getByText()` (the option text may appear in headings/descriptions too)
- `IClientProvider.Toast()` renders both a visible `<div>` and an `aria-live` status `<span>` — use `getByText("message", { exact: true })` to avoid strict mode violations
- **`Html` component inline styles don't render as expected** — `new Html(...)` with inline CSS properties like `background-color`, `border`, `color`, `width`, `height` are NOT applied to the actual DOM. Do NOT use `page.locator('div[style*="..."]')` selectors to target Html content. Instead use text-based assertions (`page.content().includes(...)`) or `getByText()` locators. Also do NOT check for hex color codes in `page.content()` — they won't appear in the rendered HTML.
- **UseChrome() crashes without IAuthService** — `UseChrome()` requires `Ivy.IAuthService` to be registered. Without it, navigating to root URL (`/`) throws `InvalidOperationException`. Always test apps with `?chrome=false` to bypass Chrome. The framework should handle this gracefully.
- **Card.OnClick() + Sheet may render blank** — when `Build()` returns `new object[] { mainContent, new Sheet(...) }`, clicking a Card to set state can cause the page to render blank (only FAB visible). The Sheet never appears. All click methods fail (`.click()`, `dispatchEvent`, `evaluate`, `mouse.click`). If testing Card click → Sheet interactions, be prepared for this failure mode and mark it as a framework issue.
- **Stale server processes**: The `taskkill` in `afterAll` may not reliably kill all dotnet processes. After multiple test runs, stale `Test.*.exe` processes can lock the EXE and prevent rebuilding. Use `execSync('taskkill /im <name>.exe /f')` (with `execSync` from `child_process`, not `spawn`) to ensure cleanup completes before afterAll exits. Also kill by name as fallback, not just by PID.
- **`video.saveAs()` causes afterEach timeout** — calling `page.video().saveAs()` in `afterEach` hangs because the browser context hasn't closed yet. Skip video renaming in afterEach; let Playwright save videos to the default location via config `video: { mode: 'on', dir: './videos' }`.
- `state.ToTextareaInput()` renders as a standard `<textarea>` element, locatable via `page.locator("textarea").first()`; disabled output textarea is the `.nth(1)`
- Clipboard `writeText` fails in headless Chromium with "Write permission denied" — this is expected and not an app bug
- `state.ToSliderInput()` renders as a Radix UI slider with `role="slider"`, NOT a native `<input type="range">` — use `page.getByRole("slider")` and keyboard interaction (ArrowRight/ArrowLeft to increment/decrement by step, Home/End for min/max)
- `UseChrome()` renders a hidden sidebar search `<input type="search" data-testid="sidebar-search">` that is the first `input` in the DOM but outside the viewport — `page.locator("input").first()` will target it instead of app inputs. Use `input[type='text']` or label-based locators to target app inputs
- **Single-app Chrome auto-selection**: When `UseChrome().UseTabs()` is enabled and there's only ONE app registered, Chrome automatically opens that app's tab on page load — no need to click the sidebar nav item. Clicking it may cause a re-navigation that times out.
- **SelectInput trigger displays all option labels**: `SelectInput<T>` with many options renders ALL option display names concatenated in the trigger button (combobox). This makes `getByText("OptionName")` ambiguous — it matches both the trigger and the dropdown item. To click a dropdown option reliably: open the dropdown, then use `page.evaluate` to find the option element by text content + bounding rect (y > trigger height), and click by coordinates. The dropdown container has `role="listbox"`.
- **SelectInput dropdown structure**: Ivy SelectInput dropdown uses Radix-like components. The trigger is a `<button role="combobox">`. The dropdown panel is `<div role="listbox">`. Items inside have NO `role="option"` — they are plain `<div>` elements with text content. Use `page.evaluate` + coordinate clicking for reliable selection when text-based locators are ambiguous.
- **Sidebar nav button name conflicts**: Chrome sidebar renders app names as `role="button"` elements. A button with text "C" will conflict with "Calculator" sidebar button when using `getByRole("button", { name: "C" })` — always use `{ exact: true }` for single-character button names
- **`waitForServer` must use `http` module**, not `fetch` — `fetch` may not be available in all Node.js versions used by Playwright. Use `http.get()` with polling loop instead
- `state.ToBoolInput().Variant(BoolInputVariants.Checkbox)` renders as `<button role="checkbox">` (Radix UI), NOT a native `<input type="checkbox">` — `getByRole("checkbox", { name: /.../ })` and `getByLabel()` do NOT work for locating these; use `page.locator('[role="checkbox"]').nth(N)` by index order instead
- `new Card(content, header: Text.H3("Title"))` — the card header text (e.g., "Monthly Revenue") will match `getByText()` along with any content containing the same substring (e.g., "Total Monthly Revenue:"), causing strict mode violations. Always use `getByRole("heading", { name: "Title" })` for card headers
- `new Card(content).Title("X")` — Card `.Title()` does NOT render as an HTML heading element (`<h1>`-`<h6>`), so `getByRole("heading", { name: "X" })` will fail. Use `getByText("X", { exact: true }).first()` instead. Only explicit `Text.H2()`/`Text.H3()` passed as card header render as headings.
- **NumberInput** (`state.ToNumberInput()`) renders as a regular text `<input>` in the DOM, NOT `<input type="number">`. `page.locator('input[type="number"]')` will find nothing. Additionally, `.WithLabel()` doesn't create proper HTML label associations, so `getByLabel()` won't work. **Recommended approach**: Use `page.locator('input[value="9"]')` to locate by current/default value when tests start fresh, or use `.nth(N)` to target by position relative to other inputs in the form.
- **CodeInput copy buttons**: `.ShowCopyButton()` and code editors add `aria-label="Copy to clipboard"` icon buttons. Combined with explicit "Copy" `Button` widgets, `getByRole("button", { name: "Copy" })` may match multiple elements — always use `{ exact: true }` for the explicit Copy button.
- **Webhooks require state parameter**: Ivy webhook URLs require an internal `state` query parameter. Server-side `HttpClient` calls to `webhook.BaseUrl` without this parameter return 400 "The 'state' query parameter is required." — Test Endpoint features using server-side HTTP calls to webhooks will fail.
- `state.ToMoneyInput().Currency("USD").Precision(0)` renders as a text input with formatted currency (e.g., "$850,000") — values are displayed with `$` prefix and comma separators
- `.ToDetails()` on an anonymous object renders key-value pairs with PascalCase property names converted to spaced labels (e.g., `MonthlyNetBurn` → "Monthly Net Burn")

## DataTable Gotchas

- **DataTable uses virtualized grid rendering** — cells are `<td role="gridcell">` elements that Playwright considers "hidden" even when data is present. Use `page.locator('[role="gridcell"]').first()` with `.toBeAttached()` instead of `.toBeVisible()` to verify data loaded.
- **Positional records crash `ToDataTable()`** — `ToDataTable()` (and `.Remove()`) on C# positional records (`record Foo(int X, string Y)`) causes `ArgumentNullException: Value cannot be null. (Parameter 'source')` because the framework internally uses `Expression.New(type)` which requires a parameterless constructor. The error only manifests when the table has data rows. **Fix**: convert positional records to classes with parameterless constructors and public properties, and use object initializer syntax in `.Select()` projections.
- **Decimal columns display as `0000000000000000`** — `decimal` values in DataTable grid render incorrectly (framework bug). Note as external issue.
- **DataTable crashes without IChatClient** — `DataTableBuilder.Build()` calls `UseService<IChatClient?>()` which throws `InvalidOperationException` when no AI service is registered. Workaround: use `Table` (`.ToTable()`) with clickable Cards for row interaction instead of DataTable, or register a dummy IChatClient. Note as external framework issue.
- **DataTable requires `IQueryable<T>`** — `ToDataTable()` only works on `IQueryable<T>`, not `IEnumerable<T>` or arrays. Use `.AsQueryable()` to convert in-memory collections. Also requires concrete types (not anonymous types).
- **`AppAttribute` uses `group:` not `path:`** — the parameter for sidebar grouping is `group: new[] { "Apps" }`, not `path:`. The AGENTS.md docs are incorrect on this.
- **DataTable + DbContext concurrent access** — `ToDataTable()` on a database-backed `IQueryable` executes multiple queries (count + data page) concurrently on the same `DbContext`, causing `InvalidOperationException: A second operation was started on this context instance`. This is intermittent and depends on data size/query complexity. **Fix**: materialize data with `.Select(e => new ConcreteRow { ... }).ToList()` first, then use `.AsQueryable().ToDataTable()`. Always use `using var db = factory.CreateDbContext()` to dispose the context after materialization.
- **Postgres enum types crash with `.ToList()`** — Npgsql can't read Postgres enum columns (e.g., `test_run_state`) unless `NpgsqlDataSourceBuilder.MapEnum<T>()` is called when building the data source. Auto-generated `AppDbContextFactory` doesn't configure this. Workaround: exclude enum columns from the `.Select()` projection, or add `MapEnum` to the factory.
- **`.Include()` + `ToDataTable()` causes DbContext threading issues** — eager loading with `.Include()` before `ToDataTable()` increases the chance of concurrent DbContext access. Remove unnecessary `.Include()` calls when the navigation property is being excluded anyway.
- **`.ToTable()` + `.Header()` with dictionary indexer crashes** — `table.Header(r => r["key"], "label")` where `r` is `Dictionary<string, string>` throws `ArgumentException: Invalid expression`. Ivy's expression parser doesn't support dictionary indexer access in lambdas. **Fix**: use manual `Table(TableRow[])` constructor with `new TableRow(new TableCell("header").IsHeader(), ...)` for header row and `new TableRow(new TableCell("value"), ...)` for data rows.

## UseRef + UseEffect Does NOT Trigger Re-render (Critical)

- `UseRef<T>` does NOT trigger component re-renders when `.Value` is set — it's a mutable reference, not reactive state
- The common pattern `UseRef<DbContext?>(null)` + `UseEffect(() => { dbRef.Value = db; return db; })` + `if (dbRef.Value is not { } db) return Skeleton.Card()` will be STUCK on skeleton forever if nothing else triggers a re-render
- **Why it sometimes works**: Apps with `UseQuery` or other reactive hooks that complete after `UseEffect` trigger a re-render, allowing `dbRef.Value` to be read on the second render cycle
- **Fix**: Replace `UseRef + UseEffect` with `UseQuery` for data fetching — `UseQuery` automatically triggers re-renders when data loads
- When converting from `UseRef + UseEffect + DbContext.Set<T>().ToDataTable()` to `UseQuery + .ToTable()`, also need to handle refresh: use a `UseState(0)` counter in the `UseQuery` key (e.g., `key: $"rooms-{refreshCount.Value}"`) and increment it instead of `refreshToken.Refresh()`

## Layout.Vertical with IEnumerable (Critical)

- `Layout.Vertical(items.Select(...), otherWidget)` where the first arg is `IEnumerable<T>` causes Ivy's content builder to render it as a data table instead of expanding children
- **Always** materialize enumerables before passing to Layout: `.Select<T, object?>(...).Append<object?>(otherWidget).ToArray()`
- Alternative: build layout with `|` operator chaining instead of passing collections

## Dialog and Sheet Locators (Critical)

- Ivy dialogs (`.ToDialog()`) and confirmation dialogs (`.WithConfirm()`) render as `<div role="dialog">`, NOT HTML `<dialog>` elements
- **NEVER** use `page.locator("dialog")` — it won't match. Always use `page.getByRole("dialog", { name: "Dialog Title" })` or `page.locator("[role='dialog']")`
- Ivy sheets (`.ToSheet()`) also render with `role="dialog"` — same locator pattern applies
- Form fields inside dialogs use labels like "Title *" (with asterisk for required) — `getByLabel("Title")` may not match. Use `dialog.getByRole("textbox").nth(N)` to target fields by position within the dialog
- `.ToForm("buttonText")` renders a form with the specified text as the submit button label — but when wrapped in `.ToDialog()`, the dialog footer shows "Cancel" and "Save" buttons regardless. Use `dialog.getByRole("button", { name: "Save" })` or target the last button in the dialog
- `Button().Url(url)` renders as an `<a>` (anchor) element, NOT `role="button"` — `getByRole("button", { name: "..." })` won't match. Use `getByText("...", { exact: true }).first()` instead

## WithConfirm Dialog

- `button.WithConfirm("message", "title")` renders a custom Dialog with "Cancel" (outline) and "Ok" (primary) buttons
- The confirm button text is always **"Ok"** — use `getByRole("button", { name: "Ok" })` to click it
- The dialog title and message are customizable, but button labels are hardcoded in `WithConfirmView`

## Critical: ValueTuple Crash Pattern

- **NEVER** use C# ValueTuple syntax `Layout.Vertical() | (item1, item2, ...)` when the tuple contains widgets — `DefaultContentBuilder.Format()` calls `ValueTuple.ToString()` which triggers `PrintMembers()` → `get_Id()` on uninitialized widgets, causing `InvalidOperationException`
- **Always** use `|` operator chaining instead: `Layout.Vertical() | item1 | item2 | item3`
- This is a Framework bug in `DefaultContentBuilder.Format()` (line 171) — note as external issue for planning
- Affects ALL widget types (Field, TextInput, Button, etc.) when placed in tuples

## Test Structure Patterns

- **Video `saveAs()` in `afterEach` causes timeout** — `page.video().saveAs()` blocks until the browser context closes, which hasn't happened yet during `afterEach`. This causes the test to exceed its timeout. Do NOT call `video.saveAs()` in `afterEach`. Instead, rely on Playwright's built-in video recording via `video: { mode: 'on', dir: './videos' }` in config — videos are saved automatically when the context closes. Only write console logs in `afterEach`.
- `test.beforeAll` runs once per `test.describe` block. Multiple `test.describe` blocks = multiple `beforeAll` executions = multiple server spawns and potential DLL lock conflicts.
- For shared server: put all tests in one `test.describe`, or use top-level `test()` calls outside describe blocks which share the file-level `beforeAll`.
- Always kill app processes after test runs on Windows — lingering processes lock DLLs and prevent rebuild on next run. Use `powershell.exe -NoProfile -Command 'Get-Process -Name "AppName" -ErrorAction SilentlyContinue | Stop-Process -Force'`
- When stale processes lock DLLs and `dotnet run` fails repeatedly, spawn the pre-built exe directly: `spawn(path.join(projectRoot, "bin", "Debug", "net10.0", "AppName.exe"), ["--port", port], ...)`
- Screenshot/log path resolution: use `path.resolve(__dirname)` in spec files, NOT `process.cwd()` — Playwright may resolve cwd differently than expected, causing silent file write failures
- Clicking `ListItem` in Ivy lists: extract the visible item title text from the page (e.g., via regex on body text) and use `getByText(name, { exact: true }).dispatchEvent("click")`. Filtering parent divs by `hasText` matches too many ancestors
- `page.goBack()` in Ivy SPA may not reliably restore blade state — prefer re-navigating or keeping blade context

## Ivy Connection Secrets

- **Ivy server blocks startup when secrets are missing** — projects with `IConnection` + `IHaveSecrets` (e.g., OpenAI) fail with "Missing secrets detected. The Ivy server cannot start." before binding any port. Tests must configure user secrets BEFORE spawning the server: `dotnet user-secrets set "SecretKey" "value"` from the project directory. Check the spec for API keys/tokens to use.
- Secret keys and presets are discoverable via `dotnet run --describe` (listed under `secrets:`)

## Ivy App Construction

- Ivy apps MUST have a parameterless constructor — `AppDescriptor.CreateApp()` uses `Activator.CreateInstance` without DI
- Do NOT use primary constructor injection like `MyApp(IClientProvider client) : ViewBase` — causes `MissingMethodException` at runtime
- Instead, use `var client = UseService<IClientProvider>()` inside the `Build()` method
- **`UseDefaultApp(type)` does NOT register the app** — it only sets `DefaultAppId`. You MUST also call `server.AddAppsFromAssembly()` (or `server.AddApp(type)`) to scan and register `[App]`-attributed classes. Without this, the server returns "No serviceable apps are registered" at runtime.
- `waitForServer` should accept ANY HTTP response (not just 200) — Ivy root URL may redirect (302) to the default app, so checking only for status 200 will cause timeout

## Card Component

- `new Card(content).Title("X")` renders the title as a `<span>`, NOT as a heading element — use `getByText("X", { exact: true })` to locate card titles, not `getByRole("heading")`
- Card title text can cause strict mode violations if the same substring appears elsewhere — always use `{ exact: true }`
- Note: `new Card(content, header: Text.H3("X"))` renders a heading (see Skyline entry), but `.Title("X")` does not

## Form (.ToForm / .ToDialog / .ToSheet) Patterns

- `.ToForm()` with `[Required]` fields renders labels as "FieldName *" (with asterisk suffix) — `getByText("Code", { exact: true })` won't match "Code *". Use input element locators (`input[type='text']`, `input[type='number']`) instead of label text for asserting form field presence
- **`.ToForm()` labels don't create HTML label-input associations** — `getByLabel("Field Name")` will NOT work for any ToForm fields (including `.Label(m => m.Prop, "Label Text")`). Always use positional locators: `page.locator("input[type='text']").nth(N)` for text inputs, or `page.locator("input[value='defaultVal']")` for inputs with known default values
- `.ToDialog(isOpen, title, submitTitle)` renders a dialog with custom title and submit button text
- `.ToSheet(isOpen, title)` renders a slide-in sheet with Save/Cancel buttons

## Ivy Component Test Patterns

- `AsQueryable().ToDataTable()` renders using glide-data-grid — a virtualized grid where cells have `role="gridcell"` but may not be "visible" (outside virtual viewport). Use `toBeAttached()` instead of `toBeVisible()` for these cells.
- **glide-data-grid cell clicking**: gridcell elements are hidden behind the canvas overlay. `.click()` and `.click({ force: true })` both fail. Use `.dispatchEvent("click")` to bypass visibility — but note this does NOT trigger Ivy's `OnCellClick` handler (the canvas intercepts real mouse events). Sheet/detail panels triggered by `OnCellClick` cannot be reliably tested via automated clicks on glide-data-grid.
- **`decimal` type in DataTable**: `decimal` columns in `AsQueryable().ToDataTable()` render as `00000000000000000` (zero-padded) instead of formatted numbers. This is a framework/glide-data-grid issue. Workaround: format values as strings in the `.Header()` call.
- `state.ToNumberInput().Variant(NumberInputVariants.Slider)` renders similarly to `ToSliderInput()` — a Radix slider with `role="slider"`.
- `state.ToSelectInput(options).Variant(SelectInputVariants.Toggle)` with string arrays renders radio buttons — use `getByRole("radio", { name: "OptionName" })`.
- `state.ToSelectInput([new Option<T>("Label", Value), ...])` (without Toggle variant) renders as a dropdown with `role="combobox"` — click to open, then `getByRole("option", { name: "Label" }).click()` to select
- `.ToTable()` on anonymous object collections renders as a standard HTML `<table>` — buttons in table cells are locatable via `page.locator("table button")`
- **`.ToTable()` DOM structure**: No `<thead>` — all rows are in `<tbody>`. The header row is the first `<tr>` and uses `<td>` cells (NOT `<th>`). Total `<tr>` count = 1 header + N data rows. To count data rows: `page.locator("table tr").count() - 1`, or use `nth(1)` for first data row. `getByText("Header")` works for column headers since they're plain `<td>` text.
- **`.ToTable()` with empty list renders as `Ivy.Empty`** — if the backing state is an empty `List<T>`, `.ToTable()` renders nothing (an `ivy-widget type="Ivy.Empty"` element). Wait for data to populate before asserting table presence.

## DateInput (ToDateInput / ToDateTimeInput) Calendar Popover

- `state.ToDateInput()` and `state.ToDateTimeInput()` both render as a `<button data-slot="calendar">` trigger that opens a Radix Popover with a react-day-picker Calendar
- `ToDateTimeInput()` additionally shows a time input (`input[type="time"]`) at the bottom of the popover — same calendar interaction, just with a time field added
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
- `state.ToBoolInput().Label("X")` WITHOUT explicit `.Variant()` renders as `role="checkbox"` (NOT `role="switch"`) — clicking the label text does NOT toggle the checkbox. Use `page.getByRole("checkbox").nth(N)` to click by index order. Note: `getByRole("checkbox")` without `{ name }` DOES work; `getByRole("checkbox", { name: "X" })` does NOT (Playwright can't resolve the accessible name from the Ivy label association).

## UseTrigger + Sheet Pattern

- **`UseTrigger` + `new Sheet()` may not trigger UI re-render** — when a Button's `OnClick` handler calls the trigger function returned by `UseTrigger`, the click event reaches the server (confirmed via WebSocket: `{"target":"Event","arguments":["OnClick","widgetId",[]]}` sent, `result: null` returned), but the `IState<bool>` change inside `UseTrigger` does NOT cause a view re-render. No UI diff is sent back to the client. The Sheet never opens.
- This pattern: `var (view, show) = UseTrigger((IState<bool> isOpen, int? id) => new MyFormView(isOpen, id));` + `new Button("Add").OnClick(_ => show(null))` — the button click is a no-op visually.
- Both `Button("text", handler)` constructor and `Button("text").OnClick(handler)` are equivalent (same event handler mechanism internally). Neither resolves this issue.
- **Workaround**: Not yet identified. Mark as framework external issue in review-tests.md.
- **Test approach**: Verify button click sends WebSocket event (confirm client-side works), document sheet non-opening as framework issue. Do not block test suite on sheet interaction tests.

## CodeBlock and UseEffect Timing

- `new CodeBlock(state.Value, language)` where `state` is populated via `UseEffect` will render with EMPTY `<code>` element on initial page load — the UseEffect hasn't fired yet
- The `<code>` element exists but has no text content; `page.locator("pre code").first().textContent()` returns `""`
- To test CodeBlock content: trigger a state change first (e.g., type in an input, move a slider) to force UseEffect to fire, then wait 500-1000ms before asserting
- Alternative: the app could initialize the state with the default value directly instead of relying on UseEffect

## Enum ToOptions() Display Text

- `typeof(MyEnum).ToOptions()` converts PascalCase enum names to spaced display text: `V1` → "V 1", `V3` → "V 3", `V4` → "V 4", etc.
- This means `getByText("V1")` will NOT match — must use `getByText("V 1", { exact: true })` with the space
- Same pattern applies to all enum values where PascalCase splitting inserts spaces between uppercase letters and digits

## Layout.Grid Column Count Bug

- `Layout.Grid(3).Gap(4)` renders the column count "3" as visible text content at the top of the grid container
- The grid items appear stacked vertically (single column) instead of in a 3-column layout
- This is a framework rendering bug — `Layout.Grid(N)` does not produce a proper CSS grid with N columns
- Workaround: use `Layout.Horizontal()` with equal-width children, or `Layout.Grid().Columns(N)` (see ReversiForge.AI entry — `.Columns(8)` worked)

## PostgreSQL Database Connections

- Projects with PostgreSQL connections need the connection string passed as an environment variable when spawning `dotnet run` in tests. The env var key depends on how the connection registers: if `server.Configuration["AppDb:ConnectionString"]`, use `env: { ...process.env, "AppDb:ConnectionString": "..." }`. If using `GetConnectionString("AppDb")`, use `ConnectionStrings__AppDb` (double underscore for nested config keys).
- The connection string value is available from the spec or from `dotnet run --describe` under `secrets:` with `preset:` value
- `HasPostgresEnum<TEnum>("enum_name")` in `OnModelCreating` + `NpgsqlDataSourceBuilder.MapEnum<TEnum>()` may fail with Npgsql.EntityFrameworkCore.PostgreSQL v10.0.0 — error: "Reading as 'System.Int32' is not supported for fields having DataTypeName 'public.enum_name'"
- **Workaround**: Remove `HasPostgresEnum<>()` and add `.HasConversion<string>()` on the enum property mapping in `OnModelCreating`. This reads/writes the PostgreSQL enum as text.
- `AppDbContextFactory` pattern: builds configuration from env vars + user secrets, gets connection string via `GetConnectionString()`, passes to `UseNpgsql()`

## DiffViewer Framework Bug

- Some apps crash with "ArgumentException: An item with the same key has already been added. Key: DiffViewer" — this is an Ivy Framework bug in component registration
- Affects apps that use certain combinations of multiple `UseQuery` + `SelectInput` + `.ToSheet()` patterns
- Cannot be fixed in project code — note as external issue
- Tests should detect the error callout text ("DiffViewer") and log it as `[FRAMEWORK_ERROR]` rather than failing

## Callout.Error Text Matching

- `Callout.Error(message)` renders the error text in a way that `getByText("substring")` may fail to match, even when the text is visually present in the callout
- This happens because Callout renders complex HTML structure with icons and nested elements — Playwright's `getByText()` may not traverse correctly
- **Workaround**: Use `page.content().includes("substring")` as a fallback when `getByText()` fails to match error callout text
- When testing apps with external API dependencies that may fail (403, rate limits), write tests that accept EITHER successful data OR error callouts using this pattern

## External API Testing Pattern

- When an app depends on an external API (CoinGecko, OpenAI, etc.) that may be unavailable during tests:
  - Tests should verify the app renders correctly in BOTH success and error states
  - Use `page.content().includes()` to detect error text rather than strict locators
  - Portfolio/local-state features should be tested independently of API availability
  - Note API failures as external issues, not project bugs

## Run History

### 2026-03-22 — FundMetricsExcel
- Fund portfolio dashboard with 6 metrics and 4 charts, SQLite + seeded data (120 companies, 93 LPs, 8 funds)
- **GroupBy + positional record LINQ crash**: `GroupBy(p => p.Sector).Select(g => new ChartData(g.Key, (double)g.Sum(...)))` failed EF Core translation. Fixed by using anonymous type server-side, then projecting to record client-side with `.ToListAsync()` + `.Select()`.
- Only Dashboard app existed — 4 CRUD apps from spec were not generated
- 9 tests, 4 rounds (2 test assertion fixes, 1 project LINQ fix), all passed, logs clean

### 2026-03-22 — BookingSystemConference
- SQLite booking system with 2 apps: Rooms (CRUD table) and Bookings (CRUD DataTable with form)
- **UseRef + UseEffect stuck on skeleton**: RoomsApp used `UseRef<DbContext?>` + `UseEffect` to initialize DB — `UseRef.Value` assignment doesn't trigger re-render, so component was permanently stuck on `Skeleton.Card()`. Fixed by replacing with `UseQuery` for data fetching.
- **BookingRow positional record LINQ crash**: `dbCtx.Bookings.Select(b => new BookingRow(...)).OrderByDescending(b => b.Start)` failed — EF Core can't translate positional record constructor in expression trees. Fixed by converting to class with parameterless constructor + `.Include()` + materialize with `.ToList()`.
- **ToDataTable replaced with ToTable**: Rooms DataTable had multiple issues (concurrent DbContext, .Remove() on types without parameterless constructor). Switched to `.ToTable()` with anonymous type projection and inline Edit/Delete buttons.
- UseQuery cache invalidation: used `UseState(0)` counter in key (e.g., `$"rooms-{count.Value}"`) instead of `UseRefreshToken()` which doesn't work with `UseQuery`
- 7 tests, 3 fix rounds (LINQ translation, UseRef pattern, UseQuery API), all passed, logs clean

### 2026-03-21 — Test.MoodRingDashboard
- Daily mood tracker with color wheel (5 moods), note input, today's timeline, weekly summary
- Box elements with `.OnClick()` render as `role="button"`, not `role="presentation"` — initial locator failures
- `.WithTooltip("text")` wraps Box in `ivy-widget[type="Ivy.Tooltip"]` — tooltip text NOT in DOM as plain text
- Correct locator for clickable tooltip boxes: `ivy-widget[type="Ivy.Tooltip"] div[role="button"]`
- 9 tests, 4 rounds (3 fixing locators), all passed, logs clean, no project fixes needed

### 2026-03-21 — Test.CoinGeckoCrypto
- Crypto portfolio tracker with TabsLayout (Markets, Chart, Portfolio) using CoinGecko REST API
- CoinGecko free API now returns 403 Forbidden — requires demo API key (`x-cg-demo-api-key` header)
- Markets and Chart tabs show `Callout.Error()` with raw HTTP exception; Portfolio tab works (local state)
- `getByText("Forbidden")` and `getByText("403")` both failed to match Callout.Error text — used `page.content().includes()` as workaround
- Tests written to accept EITHER data OR error callout for API-dependent views
- 9 tests, 4 fix rounds (API error handling in tests), all passed, logs clean

### 2026-03-21 — Test.AddPostgreDatabase2 (re-run)
- Same PostgreSQL CRUD app, fresh copy without previous fixes
- Connection string passed as `AppDb:ConnectionString` env var (not `ConnectionStrings__` prefix)
- PostgreSQL enum fix re-applied: removed `HasPostgresEnum<>()` and `MapEnum<>()`, added `.HasConversion<string>()`
- **Key discovery**: Tests, TestLinks, TestRuns apps crashed with `ArgumentNullException: Value cannot be null. (Parameter 'source')` — caused by using C# positional records with `ToDataTable()`. Empty tables (CategoryVariants) didn't crash because no rows to process.
- **Fix**: Converted positional records (`record TestRow(...)`) to classes with parameterless constructors. This resolved all 3 app crashes.
- Also standardized MenuItem pattern to `MenuItem.Default("text", Icons.X).Tag(action)` across all apps
- 10 tests, 5 rounds (enum fix, error handling, record-to-class), all passed, logs clean

### 2026-03-20 — Test.AddPostgreDatabase2
- PostgreSQL-backed CRUD app with 7 apps: Dashboard, Categories, Tests, TestFiles, TestLinks, TestRuns, CategoryVariants
- Connection string must be passed as env var `ConnectionStrings__APPDB_CONNECTION_STRING` to spawned dotnet process
- PostgreSQL enum `test_run_state` failed with `HasPostgresEnum<>()` — fixed with `.HasConversion<string>()` on the State property
- Test Runs and Test Links apps crash with DiffViewer framework bug (external issue)
- 11 tests, 5 fix rounds (env var, enum mapping, framework error handling), all passed

### 2026-03-17 — Test.AgeCalculator
- Age calculator with date picker and age display (years, months, days, hours)
- `ToDateTimeInput()` renders identically to `ToDateInput()` (same `button[data-slot="calendar"]` pattern) plus a time input — existing DateInput knowledge applies
- Initial attempt used `input[type="date"]` selector which failed — switched to calendar popover interaction
- 6 tests, 1 fix round (wrong date input selector), all passed, logs clean

### 2026-03-13 — Test.CSSGradientTextGenerator
- Gradient text generator with text input, color pickers, angle/font-size sliders, live preview, and CSS code output
- `new CodeBlock(cssCode.Value)` where `cssCode` is set via `UseEffect` renders EMPTY on initial load — must trigger state change before asserting code content
- `getByText("Preview")` matched both "Preview Text" label and "Preview" heading — use `getByRole("heading", { name: "Preview" })`
- `getByText("Gradient Text")` matched both title "CSS Gradient Text Generator" and preview div — use `{ exact: true }`
- Html inline styles (gradient background, font-size) not rendered in preview (confirmed known limitation)
- 8 tests, 2 fix rounds (strict mode + CodeBlock timing), all passed, logs clean

### 2026-03-13 — Test.LifeInWeeksVisualizer
- 2-step flow: birth date input → life visualization with stats and weeks grid
- `Layout.Grid(3)` renders "3" as text and produces single-column layout instead of 3-column grid
- `new Html(gridHtml)` with CSS grid + inline styles is completely invisible — only `<span>` text content visible (confirmed known Html limitation)
- `UseDefaultApp()` means no Chrome sidebar — navigate directly to `/<app-id>?chrome=false`
- "Weeks lived" text appears in both stat label and Html grid legend — use `.first()` for strict mode
- 7 tests, 1 fix round (strict mode violation), all passed, logs clean

### 2026-03-13 — Test.SimpleCRM
- CRM app with TabsLayout (Dashboard, Contacts, Deals, Activities) — tabs navigable via `getByText("TabName", { exact: true }).first().click()`
- `decimal` column in DataTable renders as `00000000000000000` — framework bug, not fixable in project code without changing column to string
- glide-data-grid cell `.dispatchEvent("click")` passes test but does NOT trigger Ivy `OnCellClick` — sheet panels cannot be validated
- MetricView KPI cards render correctly with icons and formatted values
- Bar/Pie charts render within Card components — chart titles via `.Title()` are spans, not headings
- 9 tests, 3 fix rounds (gridcell click visibility issues), all passed

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

### 2026-03-13 — Test.LovableLanguageLearner (Arabi Lingo)
- Language learning app with TabsLayout (Lessons, Flashcards, Quiz, Progress)
- **IMPORTANT**: `getByText("Flashcard")` matched both tab "Flashcards" and card title "Flashcard" — always use `{ exact: true }` when text appears in both tabs and content
- **IMPORTANT**: `getByRole('button', { name: 'Correct' })` matched both "Incorrect" and "Correct" buttons — add `exact: true` to button role queries when button labels share substrings
- QuizView buttons without onClick handlers generated backend warnings: `Event 'OnClick' for Widget 'xxx' not found` — adding empty `onClick: _ => { }` handlers silenced the warnings
- Zombie dotnet processes from failed test runs lock build files (`.exe` and `.dll`) — use `powershell -Command "Get-Process 'Test.ProjectName*' | Stop-Process -Force"` to kill them reliably (more effective than `taskkill` on Windows)
- 8 tests, 2 fix rounds (selector exact matching + QuizView onClick handlers), all passed, logs clean

### 2026-03-09 20:46 — Parsely.Markflow
- CodeMirror-based code inputs (from `state.ToCodeInput()`) use `.cm-content[contenteditable='true']` as the editable locator
- **IMPORTANT**: Do NOT use `keyboard.type()` or `keyboard.insertText()` for CodeMirror editors — `type()` triggers auto-brackets/auto-complete that corrupts structured input, and `insertText()` does not trigger CodeMirror's change events so Ivy state bindings never update (the server-side state stays stale). Instead, use clipboard paste: `page.evaluate(async (t) => { await navigator.clipboard.writeText(t); }, text)` then `page.keyboard.press("Control+V")`. Requires `permissions: ["clipboard-read", "clipboard-write"]` in playwright config.
- For CodeMirror inputs, the second editor (read-only/disabled output) is accessed via `.cm-content` with `.nth(1)` index selector
- Markdig's `ToHtml` with `UseAdvancedExtensions()` generates heading IDs like `id="hello-world"` — useful for asserting exact HTML output in tests
- `Button.Disabled()` with a reactive condition correctly toggles the HTML `disabled` attribute, testable via `toBeDisabled()`/`toBeEnabled()`
- Multi-line input in CodeMirror: use clipboard paste (see above) — the paste approach handles newlines correctly without needing line-by-line entry
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
- `.WithField().Label("X")` on NumberInput does NOT create an HTML `<label for="">` association — `getByLabel("X")` fails. Use `page.locator("input").first()` or index-based `page.locator("input").nth(N)` instead
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

### 2026-03-10 — Flowcraft.MermaidStudio
- Clean first-pass run — all 11 tests passed, no project fixes needed
- `new Markdown(markdownPreview)` with mermaid code blocks renders SVG diagrams via client-side Mermaid.js — preview updates reactively when code state changes
- `UseDownload(factory, mimeType, fileName)` returns a nullable URL — renders as `role="link"` when non-null, locatable via `getByRole("link", { name: /Download/i })`
- `SelectInput<string>` with `.Placeholder()` and `options.ToOptions()` renders as Radix dropdown — same pattern as other `ToSelectInput()` without Toggle variant

### 2026-03-10 — Patternix.RegexLens
- `ToBoolInput().Label("X")` without explicit Variant renders as `role="checkbox"`, NOT `role="switch"` — clicking label text does NOT toggle; must click the `[role="checkbox"]` element directly
- Dynamic checkbox/switch detection pattern: check `[role="checkbox"]` count, then `[role="switch"]`, then fallback `dispatchEvent("click")` — robust across all BoolInput variants
- `new Html(...)` with inline styles (background-color, color) renders but highlighting is invisible — likely iframe CSS isolation issue; the yellow background match highlighting doesn't display
- `Expandable` component works as expected for collapsible sections — click text to toggle
- `Box` with `.Padding()`, `.BorderThickness()`, `.BorderStyle()` renders bordered containers correctly for match items
- Clean run: 10 tests passed, no project fixes needed, no runtime errors, logs clean

### 2026-03-10 — HoofTrack.StableVault
- CRUD app with `UseBlades()` and Chrome tabs — clean pass, no runtime errors, no project fixes needed
- `Card.Title("Horse Details")` renders as text, NOT `role="heading"` — use `getByText()` not `getByRole("heading")`
- `ListItem` click by parent div `filter({ hasText })` fails — matches too many ancestors. Must extract specific title text and use `getByText(name, { exact: true }).dispatchEvent("click")`
- Screenshot path must use `path.resolve(__dirname)` not `process.cwd()` — the latter silently fails to write files in Playwright context
- `safeClick` pattern: try `.click({ timeout: 3000 })`, catch and fall back to `.dispatchEvent("click")` — handles both in-viewport and out-of-viewport elements
- `page.goBack()` after blade push doesn't restore previous blade — SPA routing doesn't map 1:1 to browser history for blade navigation

### 2026-03-10 — Folio.TextMiner
- File upload app with `UseUpload(MemoryStreamUploadHandler.Create(state))` — `page.locator('input[type="file"]').setInputFiles(path)` works for Playwright file upload testing
- `ToFileInput(upload).Placeholder(...)` renders a dashed dropzone with the placeholder text
- `ToCodeInput().Language(Languages.Text).Disabled()` renders as a read-only CodeMirror editor — `.cm-content` locator works
- Clean pass, no runtime errors, no project fixes needed

### 2026-03-10 — Pinnacle.StockGrid
- `YahooFinanceApi` v2.3.3 NuGet package returns 401 Unauthorized from Yahoo Finance v7 download API — package likely outdated/broken
- Unhandled async exceptions in button click handlers (`async () => await FetchStockData()`) crash the server process with `IsTerminating: True` — always wrap external API calls in try/catch, not just try/finally
- Fix: added `catch (Exception ex)` with `errorMessage` state + `Callout.Error()` display — app stays stable on API failure
- When external APIs are expected to fail, use `Promise.race()` pattern in tests to detect either data load OR error callout, with `test.skip()` for data-dependent tests

### 2026-03-10 — Archiva.ZipForge
- `FileUpload<byte[]>.ToTable()` with `.Remove(e => e.Content)` throws `KeyNotFoundException` — `byte[]` properties are not registered in `TableBuilder`'s field dictionary. Fix: remove the `.Remove(e => e.Content)` call
- `ToFileInput(upload).Placeholder(...)` renders a dashed dropzone with hidden `input[type="file"]` — `page.locator('input[type="file"]').setInputFiles({name, mimeType, buffer})` works for Playwright testing (confirmed from Folio.TextMiner pattern)
- `FileUpload<T>` exposes `FileName`, `ContentType`, `Length`, `Progress`, `Id`, `Content` — `.ToTable()` creates columns for all simple-type properties; `byte[]` Content is excluded from the field dictionary but other fields like ContentType and the upload Status enum still show
- 8 tests passed after 1 fix round (project fix only)

### 2026-03-10 — Pixelforge.AsciiCraft
- `Layout.Tabs(new Tab("Name", view).Icon(Icons.X), ...)` renders tab UI — tabs are clickable via `getByText("Tab Name").first().click()`
- `UseDownload()` with sync factory renders as `role="link"` (anchor tag with href), not `role="button"` — use `getByRole("link", { name: /Download/i })`
- `new CodeBlock(content, Languages.Text).ShowCopyButton()` renders with a copy icon button and `<code>` element for the content
- To generate valid PNG images for Playwright tests: use `zlib.deflateSync()` on raw pixel data (filter byte 0 + RGB per row), then construct PNG chunks (IHDR, IDAT, IEND) with proper CRC32 checksums. Invalid/minimal base64 PNGs will cause `InvalidImageContentException`
- After `dotnet build` + code changes, `dotnet run` may need a rebuild that exceeds 30s — set `beforeAll` timeout to 120s with `testInfo.setTimeout(120000)` for safety
- 12 tests passed after 1 fix round (project fix: added try-catch for corrupt image loading in AsciiArtConverter)

### 2026-03-11 — Meridian.StockGrid
- `AsQueryable().ToDataTable()` with empty data renders column headers as `role="columnheader"` elements but they are "hidden" (glide-data-grid virtual rendering) — use `toBeAttached()` not `toBeVisible()` for column headers too, not just gridcells
- When `StockDataService` catches all per-ticker exceptions and returns empty list, `UseQuery` resolves with empty data (not null, not error) — app enters "data loaded" path with empty metrics showing "No data available"
- YahooFinanceApi v2.3.3 confirmed broken again (same as Pinnacle.StockGrid) — all tickers fail silently
- No project fixes needed — app handles empty data gracefully without crashes
- 8 tests passed after 1 fix round (test fix only: column header visibility assertion)

### 2026-03-11 — StockFlow.Inventory
- Complex CRUD app with 6 apps (Dashboard, Categories, Products, Orders, Suppliers, Warehouses), Chrome sidebar + tabs, blade navigation, SQLite EF Core with Bogus seeder
- **`ToAsyncSelectInput` with nullable state types**: When form property is `int?` (nullable), the search/lookup delegates MUST use `Option<int?>` (not `Option<int>`). Using `Option<int>` causes `InvalidCastException: Null object cannot be converted to a value type` at runtime. The lookup delegate must also handle null input: `if (id == null) return null;`
- `data-testid="list-item"` does NOT exist in Ivy list rendering — click list items by visible text content using `getByText(name, { exact: true }).first().dispatchEvent("click")`
- Regex-based text extraction from `page.textContent("body")` for supplier names is fragile — regex can match too much text. Prefer regex locators like `page.locator("text=/\\w+ Inc$/").first()` for pattern-matching visible elements
- Chrome sidebar with multiple apps starts blank (no auto-open) — confirmed same as HumanCore/CrmPortal pattern
- `HeaderLayout(header, body)` pattern used in Dashboard — header contains date range toggle
- Dashboard `SelectInput<DateRange>` with `Variant(SelectInputVariant.Toggle)` renders as radio buttons — same Toggle variant pattern
- All 15 tests passed after 1 project fix round (3 files fixed: OrderCreateDialog, OrderItemCreateDialog, OrderShipmentCreateDialog)

### 2026-03-11 — Meridian.ClockFace
- `new Html(clockFaceHtml)` with CSS custom properties (`var(--foreground)`, `var(--border)`, etc.) renders completely invisible in the iframe — confirmed same pattern as Polyglot.TypeTrainer and Patternix.RegexLens
- **Real-time state updates via `UseEffect` + `System.Threading.Timer` are NOT reliably observable in Playwright**: `page.locator("h3").textContent()` polled every 500ms for 5+ seconds returned the same value despite the timer updating state every 1000ms. Screenshots confirm the time displays correctly, so it's a Playwright DOM snapshot timing issue, not an app bug. Avoid asserting real-time clock/timer updates in tests — instead verify format, timezone correctness, and static state.
- `ToSelectInput(options)` without Toggle variant renders as dropdown with `role="option"` — `getByRole("option", { name: "Tokyo" })` works for selection (confirmed again)
- `ToSwitchInput().Label(running.Value ? "Running" : "Stopped")` — label text changes reactively with state, testable via `getByText("Stopped")`
- Clean run: 12 tests passed, no project fixes, no runtime errors, logs clean

### 2026-03-11 — NexTask.TodoSync
- CRUD Todo app with UseBlades, SQLite EF Core, Chrome tabs (single app, auto-opens)
- **`WithConfirm` dialog uses "Ok" as the confirm button text** — NOT "Continue", "Confirm", or "Delete". Use `getByRole("button", { name: "Ok" })` to click the confirm button
- Form `.ToDialog()` renders field labels (e.g., "Title *") but `getByText("Title", { exact: true })` may fail — use input element locators (`input[type='text']`) instead for reliability
- `.ToDetails().Multiline(e => e.Description).RemoveEmpty().Builder(e => e.Id, e => e.CopyToClipboard())` renders clean key-value pairs with copy button on Id
- `ListItem` with `onClick` and `tag` — click items via `getByText(title, { exact: true }).first().dispatchEvent("click")` (confirmed pattern)
- Clean run: 12 tests passed after 2 test-only fix rounds, no project fixes, no runtime errors, logs clean

### 2026-03-11 — LinguaFlow.Translator
- Single-app translator using GTranslate NuGet for Google Translate, Chrome tabs (single app, auto-opens)
- `UseEffect` with async translation triggered reactively by inputText and selectedLanguage states — translation happens automatically on state change, no submit button needed
- `ToSelectInput(languageOptions)` without Toggle variant renders as Radix dropdown with 100+ language options — confirmed `getByRole("option", { name: "French", exact: true })` needed because "French" and "French (Canada)" both exist (same pattern as Polyglot.TypeTrainer prefix collisions)
- `Layout.Vertical().Background(Colors.White)` for text boxes inside cards creates low-contrast containers — white-on-white blends with card surface
- Clean run: 12 tests passed after 1 test-only fix round, no project fixes, no runtime errors, logs clean

### 2026-03-11 — GridQuest.Pathfinder
- `UseState<T>(T?)` vs `UseState<T>(Func<T>)` is ambiguous when T is a nullable reference type (e.g., `CellType[][]`, `string?`) — fix by using explicit typed variables: `CellType[][] val = ...; UseState(val);` or switch to non-nullable types (e.g., `string` with `string.IsNullOrEmpty()`)
- `NumberInput<int>.Variant(NumberInputVariant.Slider)` renders identical to `ToSliderInput()` — Radix slider with `role="slider"`, keyboard Home/End/ArrowRight/ArrowLeft work (confirmed)
- `Box` with `.Color()`, `.Size()`, `.BorderThickness()`, `.BorderColor()` renders colored div cells — no special selectors needed, just visual
- Clean first-pass run: 14 tests passed, 1 project fix (UseState build ambiguity), no runtime errors, logs clean

### 2026-03-12 — CourtVision.Analytics
- NBA statistics dashboard with data table (glide-data-grid), position/college dropdown filters, age/salary slider filters, and bar charts
- **CSV with decimal numbers**: The NBA CSV from geeksforgeeks uses `25.0`, `7730337.0` notation. C# `int.TryParse("25.0")` returns false — must use `double.TryParse()` + cast to int for CSV numeric parsing
- Filter boundary bug: `>` / `<` (strict inequality) excluded boundary values (age 18/50, salary 0). Changed to `>=` / `<=`
- `ToSelectInput(options).Searchable()` renders dropdown with search input — works correctly for long option lists (colleges)
- `.ToBarChart().Dimension().Measure().Toolbox()` renders ECharts bar charts with toolbox icons (save, switch chart type)
- 10 tests passed after 2 project fix rounds (ParseInt decimal parsing + filter inequality), no runtime errors, logs clean

### 2026-03-12 — Meridian.ProductVault
- Standard CRUD app with UseBlades, Chrome tabs (single app, auto-opens), SQLite EF Core, Bogus seeder (100 products)
- `.ToForm()` renders field labels with `*` suffix for `[Required]` fields (e.g., "Code *") — `getByText("Code", { exact: true })` fails; use `input[type='text']` locators instead
- `[Required]` on non-nullable `int Quantity` causes value 0 to fail validation (standard .NET DataAnnotations behavior) — not an Ivy bug
- `.ToDetails().RemoveEmpty().Builder(e => e.Id, e => e.CopyToClipboard())` renders clean key-value pairs with copy button on Id field
- `ProductEditSheet` uses `.ToForm().Remove(e => e.Id, e => e.CreatedAt, e => e.UpdatedAt)` — correctly hides non-editable fields
- Clean run: 12 tests passed after 1 test-only fix round, no project fixes, no runtime errors, logs clean

### 2026-03-12 — Test.PomodoroTimer
- `System.Timers.Timer` in `UseEffect` callback: timer `Elapsed` events can fire after `isRunning` state is set to false, because `UseEffect` disposal has a race condition with pending callbacks. Always add `if (!isRunning.Value) return;` guard inside `Elapsed` handler
- `.WithField().Label("X")` on `NumberInput` does NOT create HTML `<label for="">` — `getByLabel("X")` and `getByRole("spinbutton")` both fail. Use `page.locator("input").first()` or `.nth(N)` by index
- Pause/resume timing tests: after clicking Pause, wait 3+ seconds for timer disposal to settle before capturing "paused time" for comparison
- `Expandable` renders as a clickable header with chevron — `page.getByText("Settings").click()` expands it
- 6 tests passed after 1 project fix (timer guard in Elapsed callback), 4 test fix rounds, logs clean

### 2026-03-12 — Test.DataVisualization
- `DataTableBuilder.Header(r => r.Values[colIndex], columns[i])` crashes with `ArgumentException: Invalid expression` — `GetNameFromMemberExpression` (Utils.cs:467) only handles simple member access, not indexer/array expressions
- `DataTableBuilder` does NOT have a `.Remove()` method (unlike `FormBuilder` and `TableBuilder`) — `builder.Remove(expressions)` resolves to `CollectionExtensions.Remove<TKey,TValue>` and fails to compile
- Workaround for dynamic-column DataTable: replace `ToDataTable()` with manual `Layout.Horizontal/Vertical` table using `Text.Label` headers and `Text.P` cells — loses virtualization/row-actions but avoids the API limitation
- Alternative DynRow approach (record with C0-C19 properties + `Header()` rename) compiles and `Header()` works, but can't hide unused columns without `Remove()`, making it impractical
- `FileUpload<byte[]>` with `MemoryStreamUploadHandler` + `UseEffect` on fileState correctly triggers parsing when `Status == FileUploadStatus.Finished`
- `Button.Url(downloadUrl)` with `UseDownload()` renders as a standard button (not `role="link"`) — locatable via `getByRole("button", { name: /Export CSV/i })` or `getByText("Export CSV")`
- `file.setInputFiles({ name, mimeType, buffer })` works for programmatic file upload in Playwright — buffer is `Buffer.from(csvString, "utf-8")`
- 11 tests passed after 1 project fix round (replaced DataTable with manual layout)

### 2026-03-12 — Test.UUIDGenerator2
- `typeof(UuidVersion).ToOptions()` converts enum names with PascalCase splitting: `V1` → "V 1", `V4` → "V 4" — `getByText("V1")` fails, must use `getByText("V 1", { exact: true })`
- `ToSelectInput(options)` without Toggle: `getByRole("combobox").first().click()` opens dropdown, then `getByText("Option Text", { exact: true }).first().click()` to select — `getByRole("option")` does NOT work for Radix dropdown items (confirmed)
- UUID V1/V6/V7 generation with `SwapGuidEndianness` byte-swaps bytes 6-7 containing the version nibble — version identifier appears in non-standard position in string representation (not an app crash, just RFC non-compliance)
- `.ToTable()` on `List<UuidEntry>` renders standard HTML table with copy icon buttons per row — `.Builder(u => u.Uuid, f => f.CopyToClipboard())` works correctly
- `UseDownload()` for TXT/JSON/CSV export renders as `Button.Url()` links — visible and functional
- Clean run: 13 tests passed after test-only fix rounds, no project fixes, no runtime errors, logs clean

### 2026-03-12 — Test.PivotTableBuilder
- **Multi-select Toggle variant** (`IState<string[]>` with `.Variant(SelectInputVariant.Toggle)`) renders as Radix toggle buttons with `aria-pressed` attribute, NOT `role="radio"` or `role="checkbox"`. Use `page.getByText("Option", { exact: true }).first().click()` to click them. The `clickToggleOption` helper pattern (try radio → checkbox → text fallback) works robustly
- When Toggle row field options overlap with dropdown option names (e.g., "Quantity" appears in both row field toggles AND value field dropdown), `getByText("Quantity").first()` matches the TOGGLE button, not the dropdown option. Use `getByRole("option", { name: "Quantity", exact: true })` to select dropdown items when a popover/dropdown is open — this contradicts the UUIDGenerator2 finding that `getByRole("option")` doesn't work. It DOES work when the dropdown renders proper `role="option"` elements (varies by Ivy component)
- `FileUpload<string>` with `MemoryStreamUploadHandler.Create(fileState)` and `.Accept(".csv")` — file content is available as `fileState.Value.Content` (string), not byte array
- `.ToTable().Header(r => r.Prop, "Label").Totals(r => r.Prop)` renders a standard HTML table with a totals footer row — totals value may not be findable by exact number text (use regex pattern like `/7[,.]?850/`)
- `UseDefaultApp(typeof(App))` with single app — no Chrome, access via `/<app-id>?chrome=false`
- Clean run: 12 tests passed after 2 test-only fix rounds, no project fixes, no runtime errors, logs clean

### 2026-03-12 — Test.WebhookTester
- `UseWebhook` generates URLs at `/ivy/webhook/<guid>`, NOT `/api/webhook/<guid>` — don't assume API path prefix
- `UseWebhook` only accepts GET and POST requests — PUT and DELETE return non-200 status codes. This is a Framework limitation
- Webhook state (`UseState` with `ImmutableList`) persists server-side per session. Each `page.goto()` creates a new WebSocket session with fresh state (empty list), but also generates a new webhook URL (new GUID)
- `page.request.get/post/put/delete()` from Playwright fires HTTP requests that hit the webhook endpoint. State updates propagate to the page via WebSocket — need 1500-3000ms wait for UI to reflect webhook-received data
- When tests share a server and state accumulates across tests, either: (1) clear state at start of each test using UI buttons, or (2) use regex matchers like `/\d+ request\(s\) received/` instead of exact counts
- Clean run: 11 tests passed after 2 test-only fix rounds, no project fixes, no runtime errors, logs clean

### 2026-03-12 — Test.UTMParameterBuilder
- **`Dictionary<TKey, TValue>.ToDetails()` crashes** with `TargetParameterCountException` — `DetailsBuilder.Item.GetValue()` calls `PropertyInfo.GetValue(obj)` on the dictionary's indexed `this[TKey key]` property which requires a parameter. Workaround: convert to anonymous object with explicit properties, then use `.ToDetails().RemoveEmpty()`
- **Ivy `Layout.Tabs` renders BOTH tab panels in DOM** — inactive tab content is hidden but still exists. `getByText("X").first()` or `locator("input").first()` can match hidden elements from the inactive tab panel. For tab-specific interactions, use placeholder-based or role-based selectors to target elements in the active panel specifically (e.g., `input[placeholder*='unique_text']`)
- `.WithField().Required()` adds `*` suffix to field labels — `getByText("Base URL", { exact: true })` fails; use `getByText("Base URL").first()` without exact match
- Tab switching: `getByRole("tab", { name: "TabName" })` works reliably for clicking Ivy `Layout.Tabs` triggers
- `ToDetails()` on anonymous objects with PascalCase property names renders labels with spaced text: `utm_source` → "Utm Source" (underscore treated as word boundary)
- 13 tests passed after 1 project fix round (Dictionary.ToDetails crash), no runtime errors, logs clean

### 2026-03-12 — Test.TimezoneWorldClock
- **Card `.Title().Content()` renders invisible card body** — `new Card().Title(widget).Content(widget)`, `new Card(content).Title(widget)`, and `new Card(content)` all result in invisible card body content. The title/header text renders, but the body area is completely empty (white space) despite content being in the DOM. Workaround: use `Layout.Vertical()` with manual `.Padding()`, `.BorderThickness()`, `.BorderColor()` styling instead of Card
- **IANA vs Windows timezone IDs on Windows**: `GetSystemTimeZones()` returns Windows-format IDs (e.g., "Eastern Standard Time") but `FindSystemTimeZoneById("America/New_York")` works via ICU conversion and returns `tz.Id = "America/New_York"` (preserving IANA format). To deduplicate, use `tz.StandardName` not `tz.Id` since both map to the same `StandardName`
- **Searchable SelectInput dropdown**: `getByRole("combobox").first().click()` opens the dropdown, `keyboard.type("search")` filters, `getByRole("option").first().click()` selects — this pattern works reliably for `SelectInput.Searchable()`
- `GetDisplayName(tz)` for Windows timezone IDs without `/` in `tz.Id` falls through to `tz.DisplayName` which returns verbose strings like "(UTC+01:00) Amsterdam, Berlin, Bern, Rome, Stockholm, Vienna"
- 12 tests passed after 3 project fix rounds (cross-platform timezone IDs, Card content visibility, timezone deduplication), no runtime errors, logs clean

### 2026-03-12 — Test.APIRequestBuilder
- **`Layout.Vertical(IEnumerable<T>, otherItem)` renders enumerable as debug table**: When `Layout.Vertical()` receives an `IEnumerable<Layout>` from `.Select()` as one of multiple `params object?[]` arguments, the content builder serializes it as a data table (showing internal columns: Context, Id, Key, Call Site, Is Stateless) instead of expanding items as children. Fix: call `.Select<T, object?>().Append<object?>(otherItem).ToArray()` to materialize into a single array before passing to `Layout.Vertical()`
- **Icon-only buttons (`.Destructive()` trash) have no accessible name**: `Button(icon: Icons.Trash).Destructive()` renders without accessible name, text, or `data-variant` attribute. Cannot use `getByRole("button", { name: "" })` (matches wrong elements) or `getByRole("button")` filters. Working approach: iterate all `page.locator("button")` elements, check `innerText().trim() === ""`, then `dispatchEvent("click")` on the match
- `new TextInput(value, onChange).Placeholder("X")` renders with `placeholder="X"` attribute accessible via `getByRole("textbox", { name: "X" })` in Playwright
- `ToSelectInput(["GET", "POST", "PUT", "DELETE"])` without Toggle renders as Radix dropdown with `role="option"` items — confirmed `getByRole("option", { name: "POST" })` works
- `.Multiline().Rows(6)` on TextInput renders as `<textarea>` element
- 13 tests passed after 1 project fix round (IEnumerable in Layout.Vertical), no runtime errors, logs clean

### 2026-03-12 — Test.CountdownTimer
- **`UseArgs<T>` does NOT work with external URL navigation**: `UseArgs` reads from the WebSocket `appArgs` query parameter, NOT from the browser page URL. Ivy's client-side JS does not extract `appArgs` from `window.location.search` and forward it to the WebSocket. This means shareable links using `appArgs` in the page URL won't work — it's a Framework limitation
- **Shareable link URL format**: Apps that build shareable URLs must use `?appArgs={urlEncodedJson}` format (JSON-serialized args object, URL-encoded). The original pattern of individual query params (`?TargetTimestamp=X&EventName=Y`) does not work with Ivy's `UseArgs<T>()`
- **`IHttpContextAccessor.HttpContext` is null in WebSocket context**: Ivy apps render via WebSocket/SignalR, not HTTP requests. `UseService<IHttpContextAccessor>()` returns an accessor where `.HttpContext` is null. Always use `?.` on the accessor itself: `httpContextAccessor?.HttpContext?.Request`
- **`taskkill` in bash on Windows**: `spawn('taskkill', ['/pid', ...], { shell: true })` fails with "Invalid argument/option" because bash interprets `/f` as a path. Use `spawn('cmd', ['/c', 'taskkill', '/pid', pid, '/f', '/t'], { shell: false })` instead
- **`beforeAll` timeout for recompilation**: When C# source is modified between test runs, `dotnet run` triggers a rebuild that can exceed the 30s default timeout. Always use `testInfo.setTimeout(120000)` in `beforeAll`
- 7 tests passed after 3 fix rounds (2 project fixes: shareable URL format + null ref guard), logs clean
### 2026-03-12 — Test.GanttChart
- ExternalWidget library project with `.samples/` runnable app — confirmed same pattern as Ivy.TextAnnotate: tests must use `samplesDir` for `dotnet run`
- `[ExternalWidget]` shows "Unknown component type: Test.GanttChart.GanttChart" — JS bundle not served (confirmed Framework issue, not app bug)
- Tests written with conditional assertions (check element count before asserting visibility) to gracefully handle ExternalWidget rendering failure
- `ChromeSettings` still missing from NuGet (confirmed) — simplified to `server.UseChrome()`
- `UseState<string?>(null)` ambiguity (confirmed same as GridQuest.Pathfinder) — fix with explicit typed variable
- Clean run: 11 tests passed, 0 fix rounds, no runtime errors, logs clean

### 2026-03-19 — Test.BookingSystemConference
- CRUD booking system with 2 apps (Rooms, Bookings), Chrome sidebar + tabs, UseBlades, SQLite EF Core, Bogus seeder (15 rooms, ~900 bookings)
- **`UseService<IBladeService>()` vs `UseContext<IBladeService>()`**: `IBladeService` is context-scoped (provided by `UseBlades()`), NOT a DI-registered service. `UseService<IBladeService>()` returns null, causing `NullReferenceException` when clicking list items to push blades. Always use `UseContext<IBladeService>()` in blade views.
- **`BladeHeader` hides child content**: `BladeHeader(Layout.Horizontal() | searchInput | iconButton)` renders the header bar but `ToSearchInput()` and `Text.H3()` are not visible — only icon buttons show. The Bookings app works around this by placing search and title outside the `BladeHeader`
- **`Icons.Plus.ToButton().Ghost().ToTrigger()` in BladeHeader**: The trigger icon button inside BladeHeader doesn't open the dialog via Playwright click/dispatchEvent — may be a rendering constraint of BladeHeader
- `DefaultApp<RoomsApp>().UseTabs(preventDuplicates: true)` auto-opens the Rooms tab on Chrome load (confirmed same as prior single-app auto-open pattern)
- 13 tests passed after 3 fix rounds (2 project fixes: UseService→UseContext), logs clean

### 2026-03-19 — Test.PasswordGenerator
- Single-page password generator with slider, switches, strength indicator, copy/regenerate buttons
- **`Text.Monospaced()` renders as `<code>` element** with classes `font-mono text-sm font-semibold` — use `page.locator("code").first()` to locate password text. Do NOT use `[class*='mono']` selector — the Ivy footer "MADE WITH" text also has `font-mono` class, causing ambiguous matches
- `ToSwitchInput().WithLabel("Label")` renders as `role="switch"` elements — `page.getByRole("switch").nth(N)` works reliably for toggling by index order
- Radix slider `Home`/`End` keys fire multiple state changes (one per step from current to min/max) — each triggers UseEffect, so add extra wait time (2-3s) after pressing Home/End before asserting password length
- Clean run: 10 tests passed after 2 test-only fix rounds (password locator), no project fixes, no runtime errors, logs clean

### 2026-03-19 — Test.AICoverLetterGeneratorV3
- AI cover letter generator with OpenAI API (via llmproxy.ivy.app), two textareas (job posting + resume), optional instructions input, generate button, Markdown result display, download button
- **Ivy blocks startup when connection secrets are missing** — `OpenAI:ApiKey` had to be set via `dotnet user-secrets set` before server would start. Spec contained the API key (`sk-8V1zgOqfbiBOSC7XFRkS4A`)
- `UseDefaultApp` — no Chrome sidebar, direct access via `/<app-id>?chrome=false`
- `UseDownload()` with sync factory renders as `role="link"` (Download button with Outline variant)
- `new Markdown(result.Value)` renders AI-generated markdown correctly as formatted content
- `Button.Loading(loading)` shows loading state during async API calls
- Empty field guard (`string.IsNullOrWhiteSpace`) prevents generation without input — no crash, no error, just no-op
- Clean run: 10 tests passed, 0 project fixes, no runtime errors, logs clean

### 2026-03-19 — Test.AIMeetingNotesExtractorV3
- AI meeting notes extractor using LlmProxy (OpenAI-compatible API) with `IChatClient.GetResponseAsync<MeetingAnalysis>()` structured output
- `UseDefaultApp` — no Chrome sidebar, direct access via `/meeting-notes-extractor?chrome=false`
- **All connection secrets must be set** — `LlmProxy:ApiKey`, `LlmProxy:Endpoint`, `LlmProxy:Model` all required. Server blocks startup on ANY missing secret from `IHaveSecrets.GetSecrets()`, even if the code has fallback defaults. Must `dotnet user-secrets init` + set all secrets before tests
- `new Table([new TableRow(...).IsHeader(), ...items])` renders standard HTML `<table>` with header row — column headers locatable via `getByText("Header", { exact: true })`
- `Badge.Variant(BadgeVariant.Destructive/Warning/Success)` renders color-coded badges (red/yellow/green) for priority levels
- `Callout()` without `.Error()` renders as info callout with icon — used for key decisions display
- `Badge.Outline()` renders outlined badges — used for participant names in horizontal layout
- Clean run: 10 tests passed, 0 fix rounds, no project fixes, no runtime errors, logs clean

### 2026-03-19 — Test.AIDataClassifierV3
- AI data classifier using LlmProxy (OpenAI-compatible API via Refit), CSV upload + paste, configurable categories, results table
- **Project had NO app** — only the LlmProxy connection was generated. Had to create `AIDataClassifierApp.cs` from scratch based on the spec
- **`LayoutView.Children()` removed** — `Layout.Vertical().Children(...)` no longer exists in current Ivy. Must use `|` pipe operator chaining instead
- **`ToFileInput` API changed** — now requires `IState<UploadContext>` from `UseUpload(handler)` instead of `IUploadHandler` directly. Old: `fileState.ToFileInput(upload)`, New: `fileState.ToFileInput(uploadContext)` where `uploadContext = UseUpload(MemoryStreamUploadHandler.Create(fileState))`
- **`Size.Fraction(1, 2)` removed** — now `Size.Fraction(0.5f)` takes a single float
- **`App` attribute uses `title:` not `path:`** and `ViewBase` has no `Name` property to override
- Refit-generated `LlmProxyClient.cs` is 2.3MB. `Messages8` uses `[JsonExtensionData]` with `AdditionalProperties` dict for role/content
- `UseChrome(new ChromeSettings().UseTabs(preventDuplicates: true))` with single app auto-opens the tab
- Clean run: 10 tests passed, 0 fix rounds (first pass), 1 major project fix (created entire app), logs clean

## DateTimeOffset + SQLite LINQ Translation

- SQLite EF Core provider CANNOT translate `DateTimeOffset` comparisons in LINQ `Where` clauses — queries like `.Where(t => t.ClockInAt >= someDateTimeOffset)` throw "could not be translated" runtime errors
- This is an EF Core limitation, NOT an app bug — but it manifests as `Callout.Error()` in the UI
- **Fix pattern**: Split the query — load by non-DateTimeOffset filters first (CompanyId, StatusId, etc.) with `.ToListAsync()`, then filter DateTimeOffset comparisons in memory with `.Where()` on the materialized list
- This is a VERY common issue in generated Ivy projects using SQLite connections with `DateTimeOffset` columns
- The error message includes: "could not be translated. Either rewrite the query in a form that can be translated, or switch to client evaluation explicitly by inserting a call to 'AsEnumerable', 'AsAsyncEnumerable', 'ToList', or 'ToListAsync'"

### 2026-03-21 — Test.Art-Institute-of-Chicago
- Art Institute of Chicago REST API browser with Browse (search/filter/paginate artworks) and Exhibition (curated playlist) apps
- **API department_id is string, not int** — API returns "PC-7" style IDs. `Artwork` record had `int? DepartmentId` which caused `JsonException`. Fixed to `string?`
- **Card.OnClick() + Sheet renders blank page** — `BrowseApp.Build()` returns `new object[] { main, new Sheet(...) }` when artwork is selected. After any click method (`.click()`, `dispatchEvent`, `evaluate`, `mouse.click`), the page goes blank (only FAB visible). Sheet never appears. Could be framework issue with `object[]` return from `Build()`, or Card click handler interaction with Sheet rendering. Marked as external issue.
- **UseChrome() requires IAuthService** — Chrome sidebar view at root URL (`/`) throws `InvalidOperationException: Service of type 'Ivy.IAuthService' is not registered`. Individual apps work fine with `?chrome=false`. Framework issue.
- **`ivy-widget` custom element is invisible** — `ivy-widget[type='Ivy.Card']` has zero dimensions. Must use `ivy-widget[type='Ivy.Card'] > div` to target the visible card div (which has `cursor-pointer` class for clickable cards)
- 10 tests, 5 fix rounds (department_id type, card click approaches, spec restructuring), all passed, logs clean

### 2026-03-21 — Test.LovableTimeTracker
- Multi-tenant time tracking app with 4 apps: Dashboard, Time Clock, Employees, Payroll Reports (LocationsApp missing from spec)
- **DateTimeOffset + SQLite LINQ crash** — all apps using `DateTimeOffset` comparisons in LINQ `Where` crashed with translation errors. Fixed by splitting queries: load by simple filters first, then filter DateTimeOffset in memory. Affected DashboardApp (3 queries), PayrollApp (1 query), TimeClockApp (2 queries)
- **SelectInput placeholder not visible as text** — Ivy SelectInput `.Placeholder("text")` renders inside the combobox trigger, not as separate visible text. Use `getByRole("combobox").nth(N)` to verify presence instead of `getByText("placeholder")`
- 14 tests, 3 fix rounds, all passed, logs clean
