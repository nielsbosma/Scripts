# Sync Program Patterns

## Branch Configuration

- All Ivy repos (Ivy-Framework, Ivy-Agent, Ivy, Ivy-Mcp, Ivy-Tendril) use `development` as default branch. Scripts uses `main`. Ivy-Tendril added as of run 00141.

## Repository Build Notes

- **Ivy**: The `Ivy.Studio/Widgets/frontend` directory requires `pnpm install` and `pnpm run build` before `dotnet build` will succeed. Uses pnpm (has pnpm-lock.yaml, workspace: protocol — npm will fail with EUNSUPPORTEDPROTOCOL). The dist files and node_modules are gitignored.
- **Ivy (connections.slnx)**: Auto-generated Vercel client has lowercase type names triggering CS8981. Suppressed in csproj NoWarn as of run 00009.
- **Ivy.Console.slnx vp install TTY issue**: External widget projects (e.g., Ivy.Widgets.ScreenshotFeedback) use `Ivy.ExternalWidget.targets` which runs `vp install` in `frontend/`. In non-interactive shells, pnpm prompts for module purge confirmation and fails with `ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY`. Fix: set `CI=true` environment variable before building. First observed run 00170.
- **Scripts**: No .slnx files to build. Only needs git sync.

## Common Gitignore Patterns

- **.ivy/ directories**: Ivy Agent session debug logs. Should be gitignored across all repos. Fixed in Ivy-Agent (run 00020) and Ivy-Framework root (run 00020). Note: subdirectories like `src/Ivy.Agent.Filter/`, `src/Ivy.Analyser/`, `src/Ivy/` may generate new `.ivy/` dirs — added glob patterns `.ivy/` and `**/tmp_out/` to `src/.gitignore` in run 00021.
- **tmp_out/ directories**: Temporary output directories in Ivy-Framework. Gitignored as of run 00020. Extended glob in run 00021.

## Cross-Repo Namespace Migration

- **Ivy.Shared → Ivy**: Types in `Ivy-Framework/src/Ivy/Shared/` are being migrated from `namespace Ivy.Shared` to `namespace Ivy` (with `// ReSharper disable once CheckNamespace`). This affects downstream repos (Ivy-Mcp, Ivy) that `using Ivy.Shared`. When syncing, check for CS0234 errors referencing `Ivy.Shared` and update to `using Ivy`.

## API Migration Patterns

- **WidgetBase properties becoming internal**: Ivy-Framework is making WidgetBase properties (Width, Height) `internal set`, requiring downstream repos (Ivy, Ivy-Mcp) to use the fluent extension methods (`.Width()`, `.Height()`) instead of direct property assignment or object initializers. When build errors show `CS0200: Property ... cannot be assigned to -- it is read only`, convert constructor assignments and object initializers to chain the corresponding extension method. For object initializers mixing Width with other settable properties, wrap in parentheses and chain: `(new Widget { Prop = val }).Width(Size.Full())`. Fixed for Width/Height in run 00135.

## Known Issues
- **Ivy.Tendril Plans directory deleted in merges**: RECURRING (runs 00144, 00148, 00158) — AI agents resolving merge conflicts or doing large refactors in Ivy-Tendril delete `src/Ivy.Tendril/Apps/Plans/` (6 files, ~928 lines). Run 00158: deleted by commit b23eda7 (merge conflict resolution for PR #173). Fix: restore from an earlier commit with `git checkout <hash>^ -- src/Ivy.Tendril/Apps/Plans/`. Added merge conflict guidelines to AGENTS.md in run 00144 but deletions still recur.
- **Ivy-Tendril GitResult<T> API migration**: GitService methods (`GetCommitTitle`, `GetCommitDiff`, `GetCommitFiles`, `GetCommitSummaries`, `GetWorktrees`, etc.) now return `GitResult<T>` instead of plain types. Use `.IsSuccess`, `.Value`, `.GetValueOrDefault()`. `GitService.IsValidCommitHash` static method was removed — use inline regex `^[0-9a-fA-F]{7,40}$`. `WorktreeInfo.Hash` renamed to `WorktreeInfo.CommitHash`. `GitService` constructor now requires `ILogger<GitService>` parameter. `ConfigService` no longer implements `IDisposable` directly — cast with `(service as IDisposable)?.Dispose()`. First observed run 00174.
- **CS9107 primary constructor capture with -warnaserror**: When a primary constructor parameter is both captured into class state AND passed to `base(...)`, C# emits CS9107 warning. With `-warnaserror` this breaks the build. Fix: convert to regular constructor with explicit field. Observed in PlanTools, run 00174.
- **Spectre.Console 1.0 CLI migration**: Spectre.Console.Cli 1.0 changed `Command<T>.Execute` from `public override int Execute(CommandContext, T)` to `protected override int Execute(CommandContext, T, CancellationToken)`. When new CLI command files are added from older branches or restored files, they may have the old signature. Fix: update to `protected override` and add `CancellationToken cancellationToken` parameter. First observed run 00148.
- **IVYHOOK005 UseState ordering in Ivy-Tendril**: `UseState`, `UseService`, `UseEffect`, `UseRef`, `UseRefreshToken`, and other Ivy hooks must be called at the top of `Build()` methods before any non-hook statements. When code is refactored (e.g., adding filter logic), `UseState` calls can drift below non-hook code. Fix: move the `UseState` call up with the other hooks. First observed run 00152 (IceboxApp, PlansApp, ReviewApp, RecommendationsApp).
- **Ivy.Agent.Filter stale ANTLR obj**: ANTLR generates `Filters*.cs` files in `Ivy.Agent.Filter/obj/Debug/net10.0/` during build. Stale obj directory without these generated files causes CS2001 errors. Fix: `rm -rf src/Ivy.Agent.Filter/obj src/Ivy.Agent.Filter/bin` and rebuild. First observed run 00122.
- **Ivy.Tendril.slnx obj contamination**: Now in dedicated Ivy-Tendril repo. `Ivy.Tendril.Test` project is at `src/Ivy.Tendril.Test/` (sibling, not nested). Root .gitignore added in run 00141 to prevent obj/bin tracking. The repo initially had 950 tracked obj/bin files — cleaned up in run 00141.
- **Rust toolchain (dlltool.exe)**: The default Rust toolchain `stable-x86_64-pc-windows-gnu` requires `dlltool.exe` from MinGW which may not be in PATH. Ivy-Framework's Ivy.Docs.Shared project uses a Rust CLI tool during build. Fix: set `rustup override set stable-x86_64-pc-windows-msvc` in the Ivy-Framework directory (done in run 00024).
- **VBCSCompiler file locks**: `dotnet build` frequently fails on first attempt due to VBCSCompiler holding locks on DLLs. Retry usually succeeds. Consider killing VBCSCompiler processes before building.
- **Process file locks**: Running Ivy.Agent.Server, Ivy.Docs, or other dotnet processes can lock DLLs preventing builds. Kill them before building using PowerShell `Stop-Process` (bash `taskkill` can timeout). Ivy.Docs can spawn many instances (14+).
- **ivy-local respawning**: The `ivy-local.exe` process (Ivy.Console) auto-restarts immediately after being killed (likely a file watcher or service). Simply killing it is not enough — delete the exe at `Ivy.Console/bin/Debug/net10.0/ivy-local.exe` after killing, then build. The build will recreate the exe.
- **Ivy.Tendril process locks**: `Ivy.Tendril.exe` can be running (launched via `dotnet run --browse --find-available-port`) and lock DLLs in its bin/Debug directory. The parent `dotnet.exe` process must be killed first — find parent PID via `(Get-CimInstance Win32_Process -Filter 'ProcessId=<PID>').ParentProcessId`, kill the parent, then kill the child. The child may appear zombie-like briefly but will eventually terminate once the parent dotnet process is gone.
- **Microsoft Defender locks**: Defender can temporarily lock DLLs during builds. Retry usually succeeds.
- **Stale generated docs files**: Ivy-Framework's `Ivy.Docs.Shared/Generated/` can contain stale `.g.cs` files referencing types that no longer exist or were made internal (e.g., GaugeChart, SignatureInput, TabsLayout, StackLayout). Delete the `Generated/` folder before rebuilding to fix. The folder is regenerated during build. Note: the docs generator cannot handle `demo-tabs`/`demo-below` code blocks with variable declarations (statements) — only single expressions work in the inline `new Box().Content(...)` wrapper.
- **Generated code missing usings**: The Rust CLI docs generator produces `.g.cs` files that only emit `using System; using Ivy;` etc. If new code patterns use attributes (DataAnnotations, Description), helpers (UseLinks from Ivy.Docs.Helpers), or types (WidgetDocsView from Ivy.Docs.Shared.Helpers), the global usings in `Ivy.Docs.Shared/GlobalUsings.cs` must be updated. Also `TypeUtils.cs` references generated App types by class name — needs explicit usings for their namespaces (e.g., `Ivy.Docs.Shared.Apps.ApiReference.Ivy`). Current global usings include: `System.ComponentModel`, `System.ComponentModel.DataAnnotations`, `Ivy.Docs.Helpers`, `Ivy.Docs.Shared.Apps.ApiReference.Ivy`, `Ivy.Docs.Shared.Helpers`. Recurring issue — fixed in runs 00079, 00080, 00081. These usings keep getting stripped upstream; always check GlobalUsings.cs before building.
- **Ivy.Docs.Tools replaced by Rust CLI**: As of Ivy-Framework PR #3300 (commit 764ca280e), `Ivy.Docs.Tools.csproj` was removed and replaced by the Rust CLI at `src/Ivy.Docs.Tools/rust_cli/`. Any downstream repos (like Ivy-Mcp.Extractor) that referenced the C# project need to be updated to shell out to the Rust CLI instead. Fixed for Ivy-Mcp in run 00079.
- **Ivy.Console Vite PLUGIN_TIMINGS**: Rolldown/Vite emits `[PLUGIN_TIMINGS] error` to stderr for slow plugins (e.g., `vite:css`), which `-warnaserror` treats as a build error. This is a false positive — build Ivy.Console.slnx without `-warnaserror` flag.
- **Ivy.Studio vite react/jsx-runtime external**: vite-plus/Rolldown does NOT match the `"react"` external against subpath imports like `"react/jsx-runtime"`. If a `.jsx` file uses JSX, it imports `react/jsx-runtime` which must be explicitly listed in `build.rollupOptions.external` along with a globals mapping. Fixed in run 00093.
- **Internal layout types (PR #2655)**: `TabsLayout`, `StackLayout`, and `GridLayout` were made internal in Ivy-Framework to prevent LLM direct usage. Downstream repos must use public APIs (`Layout.Vertical()`, `Layout.Horizontal()`, `Layout.Tabs()`). Ivy-Agent.Test.Studio has `InternalsVisibleTo` exception because it needs `OnReorder` not exposed in public `TabView` API.
- **Ivy-Mcp NuGet vs project refs**: Ivy-Mcp.Api.Demo references `Ivy` via NuGet package, not project reference. API renames in Ivy-Framework (e.g., ChromeSettings→AppShellSettings) won't be available until a new NuGet is published. Don't rename API calls in repos using NuGet until the package is updated.
- **Security vulnerabilities**: NuGet packages may have known vulnerabilities that cause build failures with `-warnaserror`. Check `dotnet list package --outdated` and update vulnerable packages. Scriban has been a recurring issue — updated to 7.0.6 across all repos as of run 00027. Note: Ivy-Agent.Shared is a project reference consumed by Ivy — version bumps cascade and must be updated in both repos.

## Ivy Framework Logging Override

- The Ivy framework's `Server.cs` calls `SetMinimumLevel()` **after** `UseWebApplicationBuilder` mods run, overriding any level set in the mod callback. To override framework log levels from a downstream app (like Tendril), use `builder.Configuration.AddInMemoryCollection` to set `Logging:LogLevel:Default` — configuration-based rules take precedence over `SetMinimumLevel`. Fixed in run 00157.
- Tendril normal mode shows errors only. `--verbose` shows Debug+. `--quiet` shows Warning+.

## Build Strategy

- Build main/root .slnx per repo first, then sub-solutions not covered by the main one.
- Use `-warnaserror` flag to catch warnings as errors per program instructions.
- **Build order matters**: Ivy-Tendril and Ivy both have project references into Ivy-Framework (e.g., Ivy.Agent.Filter). Build Ivy-Framework first, then Ivy and Ivy-Tendril in parallel. Building Tendril before Framework completes causes MSB3030 (missing .pdb). Confirmed runs 00177.
- The Ivy repo has multiple sub-solutions (connections.slnx, Resend.slnx) that aren't part of Ivy.slnx.
- Ivy-Framework has Ivy.Analyser.slnx and Ivy.Samples.slnx as separate sub-solutions.

## Main Solutions per Repo

| Repo | Main Solution | Additional Solutions |
|---|---|---|
| Ivy-Agent | Ivy-Agent.slnx | Ivy-Agent-Client-Test.slnx, Ivy.Agent.Eval.slnx, Ivy.Lsp.Console.slnx, Ivy.Lsp.Tests.ExampleSolution.slnx |
| Ivy | Ivy.slnx | connections/connections.slnx, connections/Resend/Resend.slnx, Ivy.Console/Ivy.Console.slnx, Ivy.DotNet.Watch/Ivy.DotNet.Watch.slnx, Ivy.Hosting.Sliplane/Ivy.Hosting.Sliplane.slnx |
| Ivy-Framework | src/Ivy-Framework.slnx | src/Ivy.Analyser/Ivy.Analyser.slnx, src/Ivy.Samples/Ivy.Samples.slnx |
| Ivy-Mcp | Ivy.Mcp.slnx | - |
| Ivy-Tendril | src/Ivy.Tendril/Ivy.Tendril.slnx | - |
