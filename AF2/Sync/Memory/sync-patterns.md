# Sync Program Patterns

## Repository Build Notes

- **Ivy**: The `Ivy.Studio/Widgets/frontend` directory requires `npm run build` before `dotnet build` will succeed. The dist files are gitignored.
- **Ivy (connections.slnx)**: Auto-generated Vercel client has lowercase type names triggering CS8981. Suppressed in csproj NoWarn as of run 00009.
- **Scripts**: No .slnx files to build. Only needs git sync.
- **Ivy-Agent-Test-Data**: No .slnx files to build. Only needs git sync.

## Known Issues

- **VBCSCompiler file locks**: `dotnet build` frequently fails on first attempt due to VBCSCompiler holding locks on DLLs. Retry usually succeeds. Consider killing VBCSCompiler processes before building.
- **Process file locks**: Running Ivy.Agent.Server or other dotnet processes can lock DLLs preventing builds. Kill them before building.
- **Microsoft Defender locks**: Defender can temporarily lock DLLs during builds. Retry usually succeeds.

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
