# Sync Program Patterns

## Repository Build Notes

- **Ivy**: The `Ivy.Studio/Widgets/frontend` directory requires `npm run build` before `dotnet build` will succeed. The dist files are gitignored.
- **Ivy (connections.slnx)**: Auto-generated Vercel client has lowercase type names triggering CS8981. Suppressed in csproj NoWarn as of run 00009.
- **Scripts**: No .slnx files to build. Only needs git sync.
- **Ivy-Agent-Test-Data**: No .slnx files to build. Only needs git sync.

## Cross-Repo Namespace Migration

- **Ivy.Shared → Ivy**: Types in `Ivy-Framework/src/Ivy/Shared/` are being migrated from `namespace Ivy.Shared` to `namespace Ivy` (with `// ReSharper disable once CheckNamespace`). This affects downstream repos (Ivy-Mcp, Ivy) that `using Ivy.Shared`. When syncing, check for CS0234 errors referencing `Ivy.Shared` and update to `using Ivy`.

## Known Issues

- **VBCSCompiler file locks**: `dotnet build` frequently fails on first attempt due to VBCSCompiler holding locks on DLLs. Retry usually succeeds. Consider killing VBCSCompiler processes before building.
- **Process file locks**: Running Ivy.Agent.Server, Ivy.Docs, or other dotnet processes can lock DLLs preventing builds. Kill them before building using PowerShell `Stop-Process` (bash `taskkill` can timeout). Ivy.Docs can spawn many instances (14+).
- **Microsoft Defender locks**: Defender can temporarily lock DLLs during builds. Retry usually succeeds.
- **Stale generated docs files**: Ivy-Framework's `Ivy.Docs.Shared/Generated/` can contain stale `.g.cs` files referencing types that no longer exist (e.g., GaugeChart, SignatureInput). Delete the `Generated/` folder before rebuilding to fix. The folder is regenerated during build.

## Build Strategy

- Build main/root .slnx per repo first, then sub-solutions not covered by the main one.
- Use `-warnaserror` flag to catch warnings as errors per program instructions.
- The Ivy repo has multiple sub-solutions (connections.slnx, Resend.slnx) that aren't part of Ivy.slnx.
- Ivy-Framework has Ivy.Analyser.slnx and Ivy.Samples.slnx as separate sub-solutions.

## Main Solutions per Repo

| Repo | Main Solution | Additional Solutions |
|---|---|---|
| Ivy-Agent | Ivy-Agent.slnx | Ivy-Agent-Client-Test.slnx, Ivy.Agent.Eval.slnx, Ivy.Lsp.Console.slnx, Ivy.Lsp.Tests.ExampleSolution.slnx |
| Ivy | Ivy.slnx | connections/connections.slnx, connections/Resend/Resend.slnx, Ivy.Console/Ivy.Console.slnx, Ivy.DotNet.Watch/Ivy.DotNet.Watch.slnx, Ivy.Hosting.Sliplane/Ivy.Hosting.Sliplane.slnx |
| Ivy-Framework | src/Ivy-Framework.slnx | src/Ivy.Analyser/Ivy.Analyser.slnx, src/Ivy.Samples/Ivy.Samples.slnx |
| Ivy-Mcp | Ivy.Mcp.slnx | - |
