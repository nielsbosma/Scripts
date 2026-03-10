# My Agentic Workflow

This document describes how my agentic workflow work when working on Ivy. I mainly work on the agentic parts.

The core idea: you write (or have AI generate) **plan files** — small markdown docs that describe a single code change. Plans flow through a pipeline:

```
[Idea] → MakePlan → [.plans/] → Review/Edit → Approve → BuildApproved → [Done]
```

Plans are the unit of work. Each plan is self-contained: it has a title, problem description, solution steps, and enough context for an LLM coding agent to execute it end-to-end without human intervention.

NOTE! This workflow is changing on a daily bases. You should only use these instructions for inspiration to create your own.

---

## 1. Setup

### Repository Folder Structure

The workflow assumes a specific folder layout where all Ivy repositories live under a common parent directory, with the plans directory alongside them:

```
D:\Repos\_Ivy\
  .plans\              — Plan pipeline (shared across all repos)
  Ivy\                 — https://github.com/Ivy-Interactive/Ivy
  Ivy-Agent\           — https://github.com/Ivy-Interactive/Ivy-Agent
  Ivy-Framework\       — https://github.com/Ivy-Interactive/Ivy-Framework
  Ivy-Mcp\             — https://github.com/Ivy-Interactive/Ivy-Mcp
```

The scripts also expect a personal scripts directory:

```
D:\Repos\_Personal\Scripts\
  BuildApproved.ps1, MakePlan.ps1, ...    — All workflow scripts
  _Shared.ps1                             — Shared utility functions
  PlanContext.md                          — LLM context for plan generation
  .vscode-extensions\ivy-plans\           — VS Code extension
```

These paths are hardcoded throughout the scripts and extension. If your repos live elsewhere, update the paths in:

- `BuildApproved.ps1` — `$QueueDirs` and `$DefaultDir`
- `MakePlan.ps1` — `$plansDir` and the working directory list in the prompt
- `SplitPlan.ps1` — `$plansDir`
- `CleanPlans.ps1` — `$root`
- `ReviewCommits.ps1` — `$repos` array
- `IvyAgentRun.ps1` — build paths and server project path
- `EnsureLatestIvyFramework.ps1` — `$repoRoot`
- `PlanContext.md` — all referenced paths
- `extension.js` — hardcoded script paths in the VS Code extension

**PlanContext.md is the most important file. In this you describe everything needed to make plans for what you are working on.**

### Prerequisites

- PowerShell 7+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude`) installed and in PATH
- [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated
- Node.js / npm (for the VS Code extension and Ivy Framework frontend)
- Git
- VS Code
- [jq](https://jqlang.github.io/jq/) (for debug session analysis)

### Environment Variables

| Variable | Required | Description |
|---|---|---|
| `OPENAI_API_KEY` | Yes | API key for the LLM used by helper scripts (CreateCommit, CreatePullRequest, etc.). Despite the name, this is routed through an OpenAI-compatible endpoint — it currently calls `claude-sonnet-4-6`. |
| `OPENAI_ENDPOINT` | No | Override the API base URL. Defaults to `https://api.openai.com`. Set this if you use a proxy, Azure OpenAI, or an OpenRouter-style gateway. |
| `IVY_AGENT_DEBUG_FOLDER` | No | Path where Ivy agent debug sessions store logs and Langfuse traces (e.g. `D:\Temp\ivy-agent`). Used by `IvyAgentDebug.ps1`. |

### Installing the VS Code Extension

The extension lives at:

```
D:\Repos\_Personal\Scripts\.vscode-extensions\ivy-plans
```

**Simplest method** — create a symlink:

```cmd
mklink /D "%USERPROFILE%\.vscode\extensions\ivy-plans" "D:\Repos\_Personal\Scripts\.vscode-extensions\ivy-plans"
```

**Alternative**: Copy the folder directly into `%USERPROFILE%\.vscode\extensions\ivy-plans`.

After installing, reload VS Code. The extension activates automatically.

### Plans Directory

The scripts auto-create most subdirectories, but here's the full structure:

```
D:\Repos\_Ivy\.plans\
  approved/       — Plans ready for BuildApproved to execute
  completed/      — Successfully executed plans
  failed/         — Plans that failed execution
  history/        — Previous versions of split/updated plans
  logs/           — Execution logs from BuildApproved
  prompts/        — Saved prompts used to generate plans
  review/         — Review checklists created by BuildApproved
  skipped/        — Plans deliberately skipped
  updating/       — Plans currently being updated by Claude
```

---

## 2. The VS Code Extension (ivy-plans)

The extension adds 5 commands to VS Code, available via the Command Palette, context menu (right-click `.md` files in Explorer), and keyboard shortcuts:

| Command | Shortcut | Description |
|---|---|---|
| **Ivy: Make Plan** | `Ctrl+Alt+M` | Opens Notepad for you to type a task description, then runs `MakePlan.ps1` to generate a plan file using Claude. |
| **Ivy: Approve Plan** | `Ctrl+Alt+A` | Saves and closes the file, then moves it to the `approved/` subdirectory. `BuildApproved.ps1` picks it up from there. |
| **Ivy: Update Plan** | Context menu | Saves the file, then runs `UpdatePlan.ps1` — add `>>` comments to a plan and have Claude rewrite it incorporating your feedback. |
| **Ivy: Split Plan** | Context menu | Runs `SplitPlan.ps1` to break a multi-issue plan into separate plan files, one issue per file. |
| **Ivy: Skip Plan** | Context menu | Moves the plan to `skipped/` — for plans you want to defer. |

---

## 3. The Scripts

### Plan Lifecycle Scripts

#### `MakePlan.ps1 [-InitialPrompt <string>]`

The starting point. Opens Notepad (or accepts a prompt string) for your task description. Sends it to Claude with project context (`PlanContext.md`) and produces a numbered plan file in `.plans/`.

- Plan IDs are auto-incremented via a lock-file counter to avoid collisions when multiple plans are generated concurrently.
- Filename format: `XXX-<RepoName>-Feature-<Title>.md`
- Supports `[NNN]` references in the first line to pull in related plans as context.

#### `UpdatePlan.ps1 -PlanPath <path> [-ReadyToGo]`

Edit an existing plan. Opens it in Notepad where you add lines prefixed with `>>` to guide changes. Claude rewrites the plan incorporating your comments.

- Previous version saved to `history/`
- Updated file gets a version suffix (`-v2`, `-v3`, ...)
- Validates output completeness and retries up to 3 times if Claude truncates

#### `SplitPlan.ps1 -PlanPath <path> [-ReadyToGo]`

Takes a plan that covers multiple issues and splits it into separate single-issue plan files.

- Reserves a batch of 5 IDs upfront
- Add `>>` annotations in Notepad to guide the split
- Requires at least 2 output plans or it aborts

#### `BuildApproved.ps1 [-PollInterval <int>]`

The execution engine. Polls `.plans/approved/` for `.md` files every N seconds (default: 3).

Groups plans into **queues** by repository name (second segment of filename):

| Queue Name | Working Directory |
|---|---|
| `IvyAgent` | `D:\Repos\_Ivy\Ivy-Agent` |
| `IvyConsole` | `D:\Repos\_Ivy\Ivy` |
| `IvyFramework` | `D:\Repos\_Ivy\Ivy-Framework` |
| `IvyMcp` | `D:\Repos\_Ivy\Ivy-Mcp` |

- Queues run in **parallel** (different repos simultaneously)
- Items within each queue run **sequentially** (to avoid conflicts in the same repo)
- Each plan executes via: `claude -p <plan-content> --dangerously-skip-permissions`
- Completed plans → `completed/`, failed → `failed/`, logs → `logs/`
- Optionally creates review checklists in `review/` for non-trivial changes
- Shows a **live TUI dashboard** with running/pending/completed status

#### `CleanPlans.ps1`

Wipes all files from `completed/`, `failed/`, `history/`, `logs/`, `prompts/`, and `skipped/`. Use to reset after a batch of work.

### Git & PR Scripts

#### `CreateCommit.ps1 [-Push] [-NoVerify]`

Stages all changes, generates a conventional-commit message using an LLM (via `_Shared.ps1`'s `LlmComplete`), and commits. Optionally pushes.

#### `CreatePullRequest.ps1 [-BranchName <string>] [-Approve] [-Open] [-Reviewer <string>]`

Creates a PR from unpushed commits:

1. Generates branch name, PR title, and detailed PR body using an LLM
2. Creates the branch and pushes it
3. Creates the PR via `gh`
4. Optionally approves it, adds a reviewer, or opens it in the browser

#### `ReviewCommits.ps1`

Interactive TUI for reviewing unpushed commits across all Ivy repos (last 24 hours). For each commit you can:

- **Number**: Open a specific file's diff in VS Code
- **a**: Step through all diffs
- **o**: Open all source files in VS Code
- **m**: Launch `MakePlan` to create improvement plans from the commit
- **s**: Show full commit summary

### Ivy-Specific Scripts

#### `EnsureLatestIvyFramework.ps1`

Pulls the latest Ivy Framework, builds the frontend (npm), regenerates docs, and builds the .NET solution. Run before working on repos that depend on the framework.

#### `IvyAgentRun.ps1 [-Prompt <string>] [-WorkingDirectory <string>] [-NoBuild] [-NonInteractive] [-Debug]`

Runs the Ivy agent end-to-end:

1. Builds the console app
2. Starts the agent server on an available port
3. Creates a temp working directory (with a creative AI-generated namespace)
4. Launches the Ivy CLI
5. Optionally auto-debugs the session afterward via `IvyAgentDebug.ps1`

#### `IvyAgentRunBatch.ps1 [-Debug]`

Opens Notepad for you to enter multiple prompts (one per line), then launches each as a separate `IvyAgentRun` in its own PowerShell window with a 30-second stagger.

#### `IvyAgentDebug.ps1 [-SessionId <string>] [-Annotate] [-Prompt <string>]`

Debugs an Ivy agent session:

- Auto-detects the session ID from `.ivy/session.ldjson` if not provided
- Opens Notepad for your investigation prompt (or accepts `-Prompt` directly)
- Reads `IvyAgentDebug.md`, substitutes `{{SESSION_ID}}` and `{{PROMPT}}`, and runs Claude with the debug prompt which fetches Langfuse traces and analyzes them for hallucinations, missing FAQ entries, and process improvements

### Shared Utilities

#### `_Shared.ps1`

Imported by `CreateCommit`, `CreatePullRequest`, and `IvyAgentRun`. Provides:

| Function | Description |
|---|---|
| `LlmComplete` | Calls an OpenAI-compatible chat completions API (currently `claude-sonnet-4-6`) |
| `New-TempNamespace` | Generates creative .NET namespaces for temp directories |
| `Get-LatestTag` | Gets latest git/GitHub release tag |
| `Get-IncrementedVersion` | Bumps a semver patch version |
| `New-Release` | Creates a GitHub release via `gh` |

### Context Files

#### `PlanContext.md`

Reference context injected into `MakePlan`, `SplitPlan`, and `UpdatePlan` prompts. Contains folder structure, important file paths, and instructions for Langfuse debugging. This is **not** included in plan output — it's background info for the LLM only.

### Claude Commands

#### `IvyAgentDebug.md` (in `Scripts/`)

A standalone debug prompt template (used by `IvyAgentDebug.ps1`) that provides a comprehensive framework for analyzing Ivy agent sessions: fetching Langfuse traces, running timeline analysis, finding hallucinations, identifying missing FAQ entries, and generating improvement plans. Includes jq recipes for querying observation files.

### Tips

- **Start small**: use `MakePlan` for a single task, review the plan, approve it, and watch `BuildApproved` execute it. Get comfortable before batching.
- **Use `>>` comments** in `UpdatePlan` to iteratively refine plans. The version history is kept so you can always go back.
- **`SplitPlan`** is great for when you brainstorm a big feature and want to break it into atomic, independently-executable chunks.
- **Parallel queues** in `BuildApproved` let you work on multiple repos at once. Each repo gets its own sequential queue to avoid merge conflicts.
- **`ReviewCommits`** gives you a fast way to audit AI-generated changes before pushing. Use the `m` option to create follow-up plans from commits.
- **The plan IS the permission boundary**: `--dangerously-skip-permissions` means Claude runs with full file system access. Review plans carefully before approving.