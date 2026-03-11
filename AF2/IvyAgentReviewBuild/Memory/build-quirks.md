# Build Quirks

## dotnet clean + build race condition

After `dotnet clean`, the first `dotnet build` may fail with MSB3030 errors for Ivy.Agent.Filter outputs (dll, pdb, xml). This is because MSBuild's clean removes the dependency outputs, and the subsequent build has a race condition where Ivy.csproj tries to copy files before Ivy.Agent.Filter finishes rebuilding them.

**Fix**: Simply retry `dotnet build`. The second attempt always succeeds since the dependency outputs exist from the first partial build.
