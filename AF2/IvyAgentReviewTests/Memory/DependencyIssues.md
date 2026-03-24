# Known Dependency Issues

## Ivy Framework - Microsoft.Extensions.Configuration.Abstractions

**Issue**: Projects using the Ivy Framework may fail to run with `FileNotFoundException` for `Microsoft.Extensions.Configuration.Abstractions, Version=10.0.0.0`.

**Root Cause**: The Ivy Framework has a transitive dependency on this package through `Microsoft.Extensions.Configuration.UserSecrets`, but the dependency is not being automatically copied to consuming project outputs during build or publish.

**Symptoms**:
- `dotnet run` fails with: `Could not load file or assembly 'Microsoft.Extensions.Configuration.Abstractions, Version=10.0.0.0'`
- Error occurs at `Ivy.Server..ctor(ServerArgs args)` during server initialization
- Build succeeds but runtime fails

**Workaround** (apply to consuming projects):
```xml
<ItemGroup>
  <PackageReference Include="Microsoft.Extensions.Configuration.Abstractions" Version="10.0.5" />
</ItemGroup>
```

**Test Strategy**:
When this issue occurs during test generation:
1. Add the explicit package reference to the project's `.csproj`
2. Run `dotnet restore` and `dotnet publish -c Debug -o publish`
3. Update test spec to use the published executable: `spawn(exePath, ['--port', appPort.toString()])`
4. Set `cwd` to the publish directory in spawn options

**Notes**:
- This should be investigated and fixed at the Ivy Framework level
- The issue affects all projects that reference the Ivy Framework
- Version 10.0.5 matches the framework's transitive dependency requirement
- Document as an "External Issue" in review-tests.md for planning purposes

**First Encountered**: 2026-03-24 (URLEncoderDecoder project)
