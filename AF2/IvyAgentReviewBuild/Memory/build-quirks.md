# Build Quirks

## NETSDK1005: Stale assets file after dotnet clean

`dotnet clean` can leave a stale `obj/project.assets.json` that doesn't target the current framework (e.g. net10.0), causing NETSDK1005 on the next build. `dotnet restore` with the stale file reports "All projects are up-to-date" and does nothing.

**Fix**: Delete `obj/project.assets.json` and re-run `dotnet restore`. The subsequent build will succeed.

## dotnet clean + build race condition

After `dotnet clean`, the first `dotnet build` may fail with MSB3030 errors for Ivy.Agent.Filter outputs (dll, pdb, xml). This is because MSBuild's clean removes the dependency outputs, and the subsequent build has a race condition where Ivy.csproj tries to copy files before Ivy.Agent.Filter finishes rebuilding them.

**Fix**: Simply retry `dotnet build`. The second attempt always succeeds since the dependency outputs exist from the first partial build.

## Ivy.Analyser.dll file lock (MSB3027)

Concurrent builds or rapid retries can cause `csc` to hold a lock on `Ivy.Analyser.dll`, resulting in MSB3026 retry warnings and eventually MSB3027/MSB3021 errors. This is a transient issue in the framework dependency, not a project code problem.

**Fix**: Wait a moment and retry, or kill the locking `csc` process. The MSB3026 warnings from Ivy.Analyser are transient framework build noise — ignore them.

## IVYHOOK005: Hook ordering in Build()

The Ivy analyzer enforces that all hooks (UseState, UseEffect, UseUpload, UseDownload, etc.) are called at the top of Build(), before any non-hook statements. The analyzer appears to check declaration order — so if UseUpload comes before UseEffect, the latter triggers IVYHOOK005.

**Fix**: Order hooks as: UseState → UseEffect → UseUpload/UseDownload → non-hook code.

## IVYHOOK007: Hook called inline in expression

Hooks like `UseUpload`, `UseDownload` cannot be called inline in a method chain (e.g., `UseUpload(...).Accept(...)`). The analyzer requires hooks to be assigned to a local variable first.

**Fix**: Extract hook to variable: `var upload = UseUpload(...); var configured = upload.Accept(...);`

## IVYHOOK001B: Hooks inside lambdas

When a hook like UseDownload is called inside a lambda or helper method called from Build(), it triggers IVYHOOK001B. This commonly happens when rendering dynamic collections (e.g., a card per sheet with its own download).

**Fix**: Extract the rendering into a separate `ViewBase` subclass. Each instance gets its own Build() where the hook is at the top level. Pass the data via constructor parameter.

## IVYHOOK001 false positive inside FuncView lambdas

Static hook-helper methods (e.g. `UseProductListRecord(context, record)`) called inside a `FuncView` lambda trigger IVYHOOK001 because the analyzer flags any `UseXxx(...)` unqualified call inside a lambda/local function. The Ivy samples use this exact pattern but aren't compiled with the analyzer.

**Fix**: Qualify the call with the class name: `MyBlade.UseProductListRecord(context, record)`. The analyzer only checks unqualified identifiers and `this.X` calls, so class-qualified calls bypass the check while keeping identical behavior.

## CS0308: Table is non-generic

Agent-generated code often uses `new Table<T>(data)` but `Table` is non-generic. The correct API is `data.ToTable()` which returns `TableBuilder<T>`. Use `.Header(x => x.Prop, "Label")` for column labels (not `.Column()`).

**Important**: `.Height()`, `.Width()`, and similar layout methods return `LayoutView`, breaking the `TableBuilder<T>` fluent chain. Always place layout methods (Height, Width, etc.) **after** all `TableBuilder`-specific calls (Header, Align, ColumnWidth, Builder, etc.).

## CS1061: ToDataTable only works on IQueryable

Agent-generated code often uses `list.ToDataTable()` but `ToDataTable` is an extension on `IQueryable<T>` only. For `List<T>` or arrays, use `.ToTable()` instead.

## CS1501: TableBuilder.Header only takes 2 arguments

Agent-generated code often uses `.Header(selector, label, formatter)` with 3 arguments, but `TableBuilder.Header` only accepts `(Expression<Func<TModel, object>> field, string label)`. For custom rendering, use `.Header()` + `.Builder()`:

```csharp
.Header(e => e.Prop, "Label")
.Builder(e => e.Prop, b => b.Func((PropType x) => (object)renderResult))
```

For action columns, repurpose an existing property (e.g., Id) with a dictionary lookup:
```csharp
var byId = items.ToDictionary(e => e.Id);
.Header(e => e.Id, "Actions")
.Builder(e => e.Id, b => b.Func((int id) => { var e = byId[id]; return (object)...; }))
.Remove(e => e.UnwantedCol1, e => e.UnwantedCol2)
.Order(e => e.Col1, e => e.Col2, ...)
```

## CS1929: Badge has no Color() method

Agent-generated code often uses `new Badge("text").Color(Colors.Green)` but Badge has no `.Color()` method. Use variant methods instead: `.Success()`, `.Destructive()`, `.Secondary()`, `.Outline()`, `.Warning()`, `.Info()`, `.Primary()`.

## CS0103: Toast is not a standalone method

Agent-generated code calls `Toast("message")` directly in Build(), but Toast is an extension method on `IClientProvider`. Must obtain client first: `var client = UseService<IClientProvider>();` then call `client.Toast("message")`.

## BuilderFactory.Func type inference

Agent code uses `b.Func<double>(...)` but the method signature is `Func<TModel, TIn>(Func<TIn, object?> func)`. Use the inline type pattern from samples: `b.Func((double x) => ...)` which lets C# infer both type parameters.

## CS1929: Builder types don't have WithLabel

`DetailsBuilder<T>` and `TableBuilder<T>` don't have `.WithLabel()` - it's an extension on `IWidget`. Cast the builder to `IWidget` before calling `WithLabel`:
```csharp
var builder = data.ToDetails().Label(...);
content |= ((IWidget)builder).WithLabel("Section Label");
```
Requires `using Ivy.Core;` for `IWidget`.

## CS1503: Button icon parameter error

Agent code uses `new Button("text", Icons.Download)` but Button constructor doesn't accept an icon parameter. Use the fluent API: `new Button("text").Icon(Icons.Download)`.

## CS1660 / CS0104: ExternalWidget event handler pattern

Agent-generated ExternalWidget classes often incorrectly define event properties as `Func<Event<TWidget, TValue>, ValueTask>?`. This causes CS1660 "Cannot convert lambda expression to type 'Event<...>' because it is not a delegate type".

**Fix**: Event properties must use `Ivy.EventHandler<Event<TWidget, TValue>>?` (fully qualified to avoid ambiguity with System.EventHandler). Extension methods that accept Action<> handlers must wrap the lambda with `new(...)`:

```csharp
[Event] public Ivy.EventHandler<Event<MyWidget, string>>? OnMyEvent { get; set; }

public static MyWidget OnMyEvent(this MyWidget widget, Action<string> handler) =>
    widget with { OnMyEvent = new(e => { handler(e.Value); return ValueTask.CompletedTask; }) };
```
