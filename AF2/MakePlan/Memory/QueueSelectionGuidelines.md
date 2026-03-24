# Queue Selection Guidelines

## Queue Naming Pattern

Use `{ProjectName}{SubsystemType}` for granular queues to enable parallel processing of independent changes.

**Pattern Rules**:
- Primary project/component name as prefix (PascalCase)
- Subsystem type as suffix (e.g., Core, Tools, Analyzers, Persona, Workflows, Widgets)
- Standalone components use component name directly (e.g., TestManager)
- Fallback to base project name for cross-cutting changes

## Agent-Related Queues

| Queue | Use When | Source Paths |
|-------|----------|--------------|
| IvyAgentCore | Agent server, orchestration, core logic | Ivy.Agent.Server, Ivy.Agent (core) |
| IvyAgentBibe | Internal tooling apps | Ivy.Agent.Bibe |
| IvyAgentPersona | Persona prompts/instructions | Ivy.Agent\Agents\Personas\Prompts |
| IvyAgentWorkflows | Workflow definitions | Ivy.Internals\Workflows |
| IvyAgentAnalyzers | Analyzer implementations | Ivy.Agent\Agents\Analysers |
| IvyAgentTools | Tool implementations | Ivy.Agent\Tools |
| TestManager | Test framework | Ivy.Agent.Test.Manager |
| IvyAgentShared | Message definitions | Ivy.Agent.Shared\Messages |
| IvyAgent | Cross-cutting or uncertain | Multiple agent areas |

## Framework Queues

| Queue | Use When | Source Paths |
|-------|----------|--------------|
| IvyFrameworkWidgets | Widget implementations | Ivy-Framework\src\Ivy.Web.Widgets |
| IvyFrameworkCore | Framework core logic | Ivy-Framework\src\Ivy.Web.Core |
| IvyFramework | Cross-cutting framework changes | Ivy-Framework\src |
| IvyConsole | Console/TUI client | Ivy\Ivy.Console |
| General | Ivy repo (client+server integration) | Ivy\Ivy.Internals |

## Script Queues

| Queue | Use When | Source Paths |
|-------|----------|--------------|
| ScriptsAgents | Agentic applications | Scripts\AF2\MakePlan, IvyAgentDebug, etc. |
| ScriptsTools | Script utilities and tools | Scripts\AF2\.shared, utility scripts |
| Scripts | Cross-cutting script changes | D:\Repos\_Personal\Scripts |
| VsExtension | VS Code extensions | Scripts\AF2\.vscode-extensions |

## Other Queues

| Queue | Use When | Source Paths |
|-------|----------|--------------|
| IvyMcp | MCP service (IvyDoc, IvyQuestion) | Ivy-Mcp (GitHub issues only) |

## Independence Check

Before choosing a granular queue, verify independence:
- Does this change require other changes in different subsystems to work? → Use broader queue
- Does this only affect one subsystem? → Use `{ProjectName}{SubsystemType}` pattern
- Would blocking on unrelated changes be wasteful? → Use specific queue

## BuildApproved Sequential Processing

BuildApproved processes queues one at a time. Granular queues allow:
- Bibe UI improvements to proceed while persona changes are in progress
- Analyzer tuning to proceed independently of workflow fixes
- Tool improvements to proceed independently of server changes
- Widget additions to proceed independently of framework core changes

## Examples Applying Pattern to New Projects

If working on a new project called "FooBar" with subsystems:
- Core engine → `FooBarCore`
- CLI tools → `FooBarTools`
- UI components → `FooBarWidgets`
- Cross-cutting → `FooBar`
