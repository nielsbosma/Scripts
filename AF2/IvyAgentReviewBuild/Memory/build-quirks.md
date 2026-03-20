# Build Quirks

## dotnet clean + build race condition

After `dotnet clean`, the first `dotnet build` may fail with MSB3030 errors for Ivy.Agent.Filter outputs (dll, pdb, xml). This is because MSBuild's clean removes the dependency outputs, and the subsequent build has a race condition where Ivy.csproj tries to copy files before Ivy.Agent.Filter finishes rebuilding them.

**Fix**: Simply retry `dotnet build`. The second attempt always succeeds since the dependency outputs exist from the first partial build.

## Ivy.Analyser.dll file lock (MSB3027)

Concurrent builds or rapid retries can cause `csc` to hold a lock on `Ivy.Analyser.dll`, resulting in MSB3026 retry warnings and eventually MSB3027/MSB3021 errors. This is a transient issue in the framework dependency, not a project code problem.

**Fix**: Wait a moment and retry, or kill the locking `csc` process. The MSB3026 warnings from Ivy.Analyser are transient framework build noise — ignore them.

## IVYHOOK005: Hook ordering in Build()

The Ivy analyzer enforces that all hooks (UseState, UseEffect, UseUpload, UseDownload, etc.) are called at the top of Build(), before any non-hook statements. The analyzer appears to check declaration order — so if UseUpload comes before UseEffect, the latter triggers IVYHOOK005.

**Fix**: Order hooks as: UseState → UseEffect → UseUpload/UseDownload → non-hook code.

## IVYHOOK001B: Hooks inside lambdas

When a hook like UseDownload is called inside a lambda or helper method called from Build(), it triggers IVYHOOK001B. This commonly happens when rendering dynamic collections (e.g., a card per sheet with its own download).

**Fix**: Extract the rendering into a separate `ViewBase` subclass. Each instance gets its own Build() where the hook is at the top level. Pass the data via constructor parameter.

## IVYHOOK001 false positive inside FuncView lambdas

Static hook-helper methods (e.g. `UseProductListRecord(context, record)`) called inside a `FuncView` lambda trigger IVYHOOK001 because the analyzer flags any `UseXxx(...)` unqualified call inside a lambda/local function. The Ivy samples use this exact pattern but aren't compiled with the analyzer.

**Fix**: Qualify the call with the class name: `MyBlade.UseProductListRecord(context, record)`. The analyzer only checks unqualified identifiers and `this.X` calls, so class-qualified calls bypass the check while keeping identical behavior.

## CS0308: Table is non-generic

Agent-generated code often uses `new Table<T>(data)` but `Table` is non-generic. The correct API is `data.ToTable()` which returns `TableBuilder<T>`. Use `.Header(x => x.Prop, "Label")` for column labels (not `.Column()`).

**Important**: `.Height()`, `.Width()`, and similar layout methods return `LayoutView`, breaking the `TableBuilder<T>` fluent chain. Always place layout methods (Height, Width, etc.) **after** all `TableBuilder`-specific calls (Header, Align, ColumnWidth, Builder, etc.).
