# Sync Program Patterns

## Repository Build Notes

- **Ivy**: The `Ivy.Studio/Widgets/frontend` directory requires `npm run build` before `dotnet build` will succeed. The dist files are gitignored.
- **Ivy (connections.slnx)**: Auto-generated Vercel client has lowercase type names triggering CS8981. Suppressed in csproj NoWarn as of run 00009.
- **Scripts**: No .slnx files to build. Only needs git sync.
- **Ivy-Agent-Test-Data**: No .slnx files to build. Only needs git sync.

## Build Strategy

- Build main/root .slnx per repo first, then sub-solutions not covered by the main one.
- Use `-warnaserror` flag to catch warnings as errors per program instructions.
- The Ivy repo has multiple sub-solutions (connections.slnx, Resend.slnx) that aren't part of Ivy.slnx.
- Ivy-Framework has Ivy.Analyser.slnx and Ivy.Samples.slnx as separate sub-solutions.

## Main Solutions per Repo

| Repo | Main Solution | Additional Solutions |
|---|---|---|
| Ivy-Agent | Ivy-Agent.slnx | Ivy-Agent-Client-Test.slnx |
| Ivy | Ivy.slnx | connections.slnx, Resend.slnx |
| Ivy-Framework | src/Ivy-Framework.slnx | src/Ivy.Analyser/Ivy.Analyser.slnx |
| Ivy-Mcp | Ivy.Mcp.slnx | - |
