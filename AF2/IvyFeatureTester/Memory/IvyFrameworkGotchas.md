# Ivy Framework Gotchas

Common mistakes and issues encountered when working with the Ivy Framework during feature testing and development.

## Component API Issues

### Card Component
- ❌ **No `.Default()` method**: `Card.Default()` does NOT exist
- ✅ **Use**: `new Card(content)` or `Layout.Vertical()` containers

### TestId Support
- ❌ **Not universal**: `.TestId()` only works on `WidgetBase` types
- ❌ **Doesn't work on**: `TextBuilder`, `LayoutView`, and other non-widget types
- ✅ **Workaround**: Put TestIds on actual widgets (inputs, buttons, cards), not on layouts or text

### Icons Enum
- ❌ **Not all Lucide icons available**: Some expected names don't exist (e.g., `Icons.AlignCenter`)
- ✅ **Use correct names**: `Icons.AlignCenterHorizontal` instead
- 📝 **Note**: Lucide renamed some icons (e.g., `AlertTriangle` → `TriangleAlert`)

## Hook Rules (Critical)

### Hook Ordering - IVYHOOK005
**All Ivy hooks MUST be called at the very top of `Build()` method, before ANY other statements.**

❌ **WRONG - Causes IVYHOOK005 warning:**
```csharp
public override object? Build() {
    var state1 = UseState<int>(() => 0);
    var value = state1.Value * 2;        // ❌ Logic between hooks
    var state2 = UseState<string>("");   // ❌ Hook after logic
    return Layout.Vertical() | ...;
}
```

✅ **CORRECT - All hooks first:**
```csharp
public override object? Build() {
    // All hooks at the top
    var state1 = UseState<int>(() => 0);
    var state2 = UseState<string>(() => "");
    var service = UseService<IClientProvider>();

    // Then logic
    var value = state1.Value * 2;
    return Layout.Vertical() | ...;
}
```

**Why this matters**: Ivy's hook system relies on consistent call order across renders. Conditional or out-of-order hooks break state tracking and cause runtime errors.

## Frontend Build Issues

### Stale Frontend Assets
**Problem**: When testing commits that change TypeScript files in `src/frontend/`, the server may serve old bundled JS.

**Why**: Frontend assets are built into `src/frontend/dist/` and embedded into `Ivy.dll` via `<EmbeddedResource>`. Running `dotnet run` uses the already-compiled DLL with old assets.

✅ **Solution**: Always rebuild frontend before testing:
```bash
cd /d/Repos/_Ivy/Ivy-Framework/src/frontend
npm run build
```

Then run your test project.

## Project Setup Issues

### Missing using Directive
**Problem**: Compilation errors for `ViewBase`, `Icons`, etc. in test apps.

❌ **WRONG:**
```csharp
namespace MyTest;

[App(icon: Icons.Settings)]
public class MyApp : ViewBase { }  // ❌ ViewBase not found
```

✅ **CORRECT:**
```csharp
using Ivy;  // ✅ Add this

namespace MyTest;

[App(icon: Icons.Settings)]
public class MyApp : ViewBase { }
```

### App Registration
**Problem**: Apps don't appear when running the server.

**Why**: Ivy does NOT auto-discover apps. They must be explicitly registered.

✅ **Required in Program.cs:**
```csharp
var server = new Server();
server.AddAppsFromAssembly(Assembly.GetExecutingAssembly());  // ✅ Required
await server.RunAsync();
```

### Nullable Enable Required
**Problem**: CS8632 warnings about nullable reference types.

✅ **Solution**: Add to `.csproj`:
```xml
<PropertyGroup>
  <Nullable>enable</Nullable>
</PropertyGroup>
```

## Common Compilation Errors

### Button Variant
❌ **No `ButtonVariant.Default`** - it doesn't exist
✅ **Use**: `Primary`, `Destructive`, `Outline`, `Secondary`, `Success`, `Warning`, `Info`, `Ghost`, `Link`

### State Pipe Method
❌ **`state.Pipe()` doesn't exist** on `IState<T>`
✅ **Workaround**: Use inline expressions or extract to local variable before passing to layout

### AppBase vs ViewBase
❌ **Don't use `AppBase`** for test apps
✅ **Use `ViewBase`** - it's the correct base class for Ivy views

## Ivy.Analyser Integration

### Local Analyser Reference
When adding Ivy.Analyser to test projects:

✅ **Correct ProjectReference:**
```xml
<ProjectReference Include="D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Analyser\Ivy.Analyser.csproj"
                  OutputItemType="Analyzer"
                  ReferenceOutputAssembly="false" />
```

**Critical attributes:**
- `OutputItemType="Analyzer"` - Tells MSBuild this is a Roslyn analyzer
- `ReferenceOutputAssembly="false"` - Analyzer runs at compile-time only

### Analyser Catches Issues
The analyser enforces Ivy-specific rules at compile time:
- **IVYHOOK005**: Hook ordering violations (hooks must be called first)
- More rules added over time

**Pro tip**: Run `dotnet clean && dotnet build` to see analyser warnings after adding it.

## Lessons Learned

### 1. Always Check Source Code
Don't assume API methods exist based on patterns from other components. Read the actual source code in `D:\Repos\_Ivy\Ivy-Framework\src\Ivy\` before using any API.

### 2. Frontend Changes Require Rebuild
Testing commits with `.ts` file changes? Frontend rebuild is NOT optional.

### 3. TestId Strategically
Since TestId only works on widgets, plan your test structure around actual widget boundaries, not layouts.

### 4. Use Ivy.Analyser Early
Add the analyser to test projects immediately. It catches issues at compile-time that would otherwise cause runtime errors or subtle bugs.

### 5. Hook Rules Are Strict
The hook ordering rule (all hooks first) is non-negotiable. The analyser will catch violations, but understanding why helps write better code from the start.

## Serialization / CamelCase Issues

### DataKey String Values Are NOT CamelCased
**Problem**: Ivy's `WidgetSerializer` uses `JsonNamingPolicy.CamelCase` for property names and dictionary keys. But string VALUES (like `DataKey`) are sent as-is.

This means data property names get camelCased during serialization, but the DataKey used to look them up on the frontend stays PascalCase.

- Data `new { Height = 165 }` serializes to `{"height": 165}`
- `XAxis("Height").DataKey` serializes as the string `"Height"`
- Frontend: `d["Height"]` is `undefined` because the key is `"height"`

**Fix applied in ScatterChartWidget.tsx**: Added `resolveValue()` helper that tries both original key and camelCase fallback.

**Note**: This pattern may affect other chart widgets or any widget that uses DataKey to look up values in serialized data objects. Watch for similar issues when testing new chart types.

### Reference Markers (ReferenceDot/Line/Area) — Format Mismatch
**Problem**: C# `ReferenceLine`, `ReferenceArea`, `ReferenceDot` are simple records (`{ x, y, label }`), but the frontend code (both `ScatterChartWidget.tsx` and `sharedUtils.ts`) assumed they arrived as ECharts-native `MarkLine`/`MarkArea` objects (with `data` arrays). Calling `.flatMap(ml => ml.data)` on a C# record fails because there's no `data` property.

**Fix applied in ScatterChartWidget.tsx**: Transform C# records to ECharts format:
- `ReferenceLine { x, y }` → `markLine.data` entries using `xAxis`/`yAxis` keys
- `ReferenceArea { x1, y1, x2, y2 }` → `markArea.data` pairs
- `ReferenceDot { x, y }` → `markPoint.data` with `coord: [x, y]`

**Note**: The SAME bug exists in `sharedUtils.ts` `generateSeries()`, which is used by BarChart, LineChart, and AreaChart. Those widgets' reference markers are also broken and need the same transformation fix.

## RadialBarChart

### RadialBar.Name() doesn't exist
`.Name()` is an `AxisBase<T>` extension, not available on `RadialBar`. Use the constructor's second parameter instead.

- `new RadialBar("dataKey", "Display Name")` - correct
- `new RadialBar("dataKey").Name("Display Name")` - compile error (CS0311)

### RadialBarChart TypeScript circular reference
The `useMemo` callback must NOT reference `option.polar` while building `option`. Build polar config in a separate variable first.

## Calendar Widget

### Enum PascalCase vs lowercase in Frontend
C# enum `CalendarDisplayMode.Week` serializes as `"Week"` (PascalCase), but the frontend CalendarView type uses lowercase `'week'`. Always normalize with `.toLowerCase()` when receiving C# enum values on the frontend.

### Widget Children Pattern (Calendar/Kanban)
To pass structured children to a widget on the frontend:
1. Add child type filter in `WidgetRenderer.tsx` (both memoized and external paths)
2. Use `widgetNodeChildren` prop in the widget component for metadata
3. Use `slots.default[index]` for rendered React content at matching index
4. Register both parent and child widgets in `widgetMap.ts`

### WidgetRenderer.tsx File Casing Issue
Git tracks this file as `widgetRenderer.tsx` (lowercase) but the file on disk is `WidgetRenderer.tsx` (PascalCase). Existing imports use lowercase (`@/widgets/widgetRenderer`). This pre-existing mismatch causes TS1261 errors when the file is modified. Use `npx vite build` directly to bypass the `tsc -b` check if needed.

## Future Gotchas to Document

As we encounter more issues during feature testing, add them here with:
- ❌ **What doesn't work**
- ✅ **What does work** (solution)
- 📝 **Why** (explanation when helpful)
- Code examples showing wrong vs. right approach
