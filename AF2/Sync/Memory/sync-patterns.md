# Sync Program Patterns

## Repository Build Notes

- **Ivy**: The `Ivy.Studio/Widgets/frontend` directory requires `npm install` and `npm run build` before `dotnet build` will succeed. The dist files and node_modules are gitignored.
- **Ivy (connections.slnx)**: Auto-generated Vercel client has lowercase type names triggering CS8981. Suppressed in csproj NoWarn as of run 00009.
- **Scripts**: No .slnx files to build. Only needs git sync.

## Common Gitignore Patterns

- **.ivy/ directories**: Ivy Agent session debug logs. Should be gitignored across all repos. Fixed in Ivy-Agent (run 00020) and Ivy-Framework root (run 00020). Note: subdirectories like `src/Ivy.Agent.Filter/`, `src/Ivy.Analyser/`, `src/Ivy/` may generate new `.ivy/` dirs — added glob patterns `.ivy/` and `**/tmp_out/` to `src/.gitignore` in run 00021.
- **tmp_out/ directories**: Temporary output directories in Ivy-Framework. Gitignored as of run 00020. Extended glob in run 00021.

## Cross-Repo Namespace Migration

- **Ivy.Shared → Ivy**: Types in `Ivy-Framework/src/Ivy/Shared/` are being migrated from `namespace Ivy.Shared` to `namespace Ivy` (with `// ReSharper disable once CheckNamespace`). This affects downstream repos (Ivy-Mcp, Ivy) that `using Ivy.Shared`. When syncing, check for CS0234 errors referencing `Ivy.Shared` and update to `using Ivy`.

## Known Issues
- **Rust toolchain (dlltool.exe)**: The default Rust toolchain `stable-x86_64-pc-windows-gnu` requires `dlltool.exe` from MinGW which may not be in PATH. Ivy-Framework's Ivy.Docs.Shared project uses a Rust CLI tool during build. Fix: set `rustup override set stable-x86_64-pc-windows-msvc` in the Ivy-Framework directory (done in run 00024).
- **VBCSCompiler file locks**: `dotnet build` frequently fails on first attempt due to VBCSCompiler holding locks on DLLs. Retry usually succeeds. Consider killing VBCSCompiler processes before building.
- **Process file locks**: Running Ivy.Agent.Server, Ivy.Docs, or other dotnet processes can lock DLLs preventing builds. Kill them before building using PowerShell `Stop-Process` (bash `taskkill` can timeout). Ivy.Docs can spawn many instances (14+).
- **Microsoft Defender locks**: Defender can temporarily lock DLLs during builds. Retry usually succeeds.
- **Stale generated docs files**: Ivy-Framework's `Ivy.Docs.Shared/Generated/` can contain stale `.g.cs` files referencing types that no longer exist (e.g., GaugeChart, SignatureInput). Delete the `Generated/` folder before rebuilding to fix. The folder is regenerated during build. Note: the docs generator cannot handle `demo-tabs`/`demo-below` code blocks with variable declarations (statements) — only single expressions work in the inline `new Box().Content(...)` wrapper.
- **`vp` command not found**: Ivy-Framework frontend build uses `vp install` / `vp run build` (a Volta-based tool). When `vp` is unavailable, manually run `pnpm install` + `pnpm run build` in `src/frontend/`, then `touch src/frontend/dist/.build-stamp` and `touch src/frontend/node_modules/.modules.yaml` to satisfy MSBuild's incremental build checks. The stamp must be re-touched whenever source files change.
- **Ivy-Mcp NuGet vs project refs**: Ivy-Mcp.Api.Demo references `Ivy` via NuGet package, not project reference. API renames in Ivy-Framework (e.g., ChromeSettings→AppShellSettings) won't be available until a new NuGet is published. Don't rename API calls in repos using NuGet until the package is updated.
- **Security vulnerabilities**: NuGet packages may have known vulnerabilities that cause build failures with `-warnaserror`. Check `dotnet list package --outdated` and update vulnerable packages. Fixed: Scriban 6.6.0 → 7.0.3 in Ivy-Mcp (run 00020). Scriban 6.6.0 → 7.0.5 in Ivy-Agent and 7.0.3 → 7.0.5 in Ivy (run 00022). Note: Ivy-Agent.Shared is a project reference consumed by Ivy — version bumps cascade and must be updated in both repos.

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
