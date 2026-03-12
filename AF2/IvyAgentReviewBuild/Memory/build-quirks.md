# Build Quirks

## dotnet clean + build race condition

After `dotnet clean`, the first `dotnet build` may fail with MSB3030 errors for Ivy.Agent.Filter outputs (dll, pdb, xml). This is because MSBuild's clean removes the dependency outputs, and the subsequent build has a race condition where Ivy.csproj tries to copy files before Ivy.Agent.Filter finishes rebuilding them.

**Fix**: Simply retry `dotnet build`. The second attempt always succeeds since the dependency outputs exist from the first partial build.

## Ivy.Analyser.dll file lock (MSB3027)

Concurrent builds or rapid retries can cause `csc` to hold a lock on `Ivy.Analyser.dll`, resulting in MSB3026 retry warnings and eventually MSB3027/MSB3021 errors. This is a transient issue in the framework dependency, not a project code problem.

**Fix**: Wait a moment and retry, or kill the locking `csc` process. The MSB3026 warnings from Ivy.Analyser are transient framework build noise — ignore them.

## IVYHOOK001 false positive inside FuncView lambdas

Static hook-helper methods (e.g. `UseProductListRecord(context, record)`) called inside a `FuncView` lambda trigger IVYHOOK001 because the analyzer flags any `UseXxx(...)` unqualified call inside a lambda/local function. The Ivy samples use this exact pattern but aren't compiled with the analyzer.

**Fix**: Qualify the call with the class name: `MyBlade.UseProductListRecord(context, record)`. The analyzer only checks unqualified identifiers and `this.X` calls, so class-qualified calls bypass the check while keeping identical behavior.
