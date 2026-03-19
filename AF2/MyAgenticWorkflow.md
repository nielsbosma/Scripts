# My Agentic Workflow

This document describes how my agentic workflow works when working on Ivy. I mainly work on the agentic parts.

The core idea: you write (or have AI generate) **plan files** — small markdown docs that describe a single code change. Plans flow through a pipeline:

```
[Idea] → MakePlan → [.plans/] → Review/Edit → Approve → BuildApproved → [Done]
```

Plans are the unit of work. Each plan is self-contained: it has a title, problem description, solution steps, and enough context for an LLM coding agent to execute it end-to-end without human intervention.

NOTE! This workflow is changing on a daily basis. You should only use these instructions for inspiration to create your own.

---

## 1. Architecture: The Firmware Pattern

The workflow uses a **firmware-based agentic application architecture**. Each tool is a self-evolving Claude Code agent with a standardized structure:

```
AF2/
  .shared/                  — Shared infrastructure
    Firmware.md             — Template prompt injected into every agent (never changes)
    Utils.ps1               — PowerShell utilities (log files, firmware prep, arg collection)
    Paths.md                — Important paths and files across the Ivy ecosystem
    Repos.md                — List of all managed repositories
    Feedback.md             — Instructions for processing user feedback (-Feedback flag)
  MakePlan/                 — Example application folder
    Program.md              — The agent's instructions (evolves over time)
    Memory/                 — Persistent memory (markdown files with learnings)
    Tools/                  — Reusable PowerShell tools created by the agent
    Logs/                   — Numbered execution logs (00001.md, 00002.md, ...)
  MakePlan.ps1              — Thin launcher script
  BuildApproved.ps1         — Standalone script (not firmware-based)
  ...
```

### How It Works

1. **Launcher** (`MakePlan.ps1`) — A ~20-line PowerShell script that:
   - Collects arguments (from CLI or opens Notepad)
   - Creates a numbered log file
   - Prepares the firmware by filling in template placeholders
   - Launches `claude --dangerously-skip-permissions` with the firmware prompt

2. **Firmware** (`.shared/Firmware.md`) — A template prompt that never changes. It:
   - Tells Claude it's an "agentic application that evolves over time"
   - Points to the Program.md, Memory/, Tools/, and Logs/ for this specific app
   - Requires the agent to read Program.md, list tools, list memory at startup
   - Requires a **reflection step** at the end of every execution to learn and improve
   - Supports a `-Feedback` flag to let users provide improvement feedback

3. **Program** (`Program.md`) — The actual task instructions. This file **evolves over time** as the agent adds learnings and new instructions during reflection.

4. **Memory** — Persistent markdown files the agent reads and writes to accumulate knowledge across sessions.

5. **Tools** — PowerShell scripts the agent creates for itself to reuse across executions.

6. **Logs** — Sequential numbered markdown files recording each execution's outcome.

### The Self-Improvement Loop

Every execution ends with a reflection step where the agent asks: "What did I learn?" It can:
- Add instructions to `Program.md`
- Create or update memory files
- Create reusable tools
- Prune outdated memory

This means **the agents get better at their jobs over time** — they learn project-specific patterns, accumulate domain knowledge, and build up tooling.

### Making Your Own Application

To create a new agentic application:

1. Create a launcher script (copy any existing `.ps1` like `MakePlan.ps1`)
2. Create a folder with the same name (minus `.ps1`) containing at minimum a `Program.md`
3. Write your task instructions in `Program.md`
4. The firmware handles the rest — Memory/, Tools/, and Logs/ directories are created automatically

The `Utils.ps1` provides helper functions:
- `GetProgramFolder` — Derives the application folder from the script path
- `GetNextLogFile` — Creates the next sequential log file
- `PrepareFirmware` — Fills in the firmware template with args, paths, session IDs
- `CollectArgs` — Collects arguments from CLI or opens Notepad if none provided
- `InvokeOrOutputPrompt` — Runs Claude or outputs the prompt for debugging

---

## 2. Setup

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

The scripts directory:

```
D:\Repos\_Personal\Scripts\AF2\
  .shared\                          — Shared firmware, utils, paths
  .vscode-extensions\ivy-plans\     — VS Code extension
  MakePlan.ps1 + MakePlan/          — Plan generation agent
  BuildApproved.ps1                 — Plan execution engine
  ExecutePlan.ps1                   — Execute a single plan file
  Sync.ps1 + Sync/                  — Repository sync agent
  MakePrs.ps1 + MakePrs/            — PR creation agent
  CreateCommit.ps1 + CreateCommit/  — Commit creation agent
  CreateIssue.ps1 + CreateIssue/    — Issue creation agent
  CreatePullRequest.ps1 + CreatePullRequest/ — PR creation agent (single repo)
  UpdatePlan.ps1 + UpdatePlan/      — Plan update agent
  SplitPlan.ps1 + SplitPlan/        — Plan splitting agent
  IvyAgentDebug.ps1 + IvyAgentDebug/        — Session debugging agent
  IvyAgentReviewBuild.ps1 + IvyAgentReviewBuild/    — Build review agent
  IvyAgentReviewLangfuse.ps1 + IvyAgentReviewLangfuse/ — Langfuse review agent
  IvyAgentReviewSpec.ps1 + IvyAgentReviewSpec/    — Spec review agent
  IvyAgentReviewTests.ps1 + IvyAgentReviewTests/  — Test review agent
  IvyFeatureTester.ps1 + IvyFeatureTester/  — Feature testing agent
  IvyFeatureInspect/                — Feature inspection
  IvyGenerateTests/                 — Test generation
  ReviewCommits.ps1                 — Interactive commit review TUI
  CleanPlans.ps1                    — Reset plan directories
  EnsureLatestIvyFramework.ps1      — Build framework from source
```

Hardcoded paths appear throughout. If your repos live elsewhere, update:
- `BuildApproved.ps1` — `$QueueDirs` and `$DefaultDir`
- `ExecutePlan.ps1` — `$QueueDirs` and `$DefaultDir`
- `.shared/Paths.md` — all referenced paths
- `.shared/Repos.md` — list of repositories
- `extension.js` — hardcoded script paths in the VS Code extension
- Individual `Program.md` files that reference specific paths

### Prerequisites

- PowerShell 7+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude`) installed and in PATH
- [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated
- Node.js / npm (for the VS Code extension and Ivy Framework frontend)
- Git
- VS Code

### Environment Variables

| Variable | Required | Description |
|---|---|---|
| `OPENAI_API_KEY` | Yes | API key for the LLM used by helper scripts (CreateCommit, CreatePullRequest, etc.). Despite the name, this is routed through an OpenAI-compatible endpoint — it currently calls `claude-sonnet-4-6`. |
| `OPENAI_ENDPOINT` | No | Override the API base URL. Defaults to `https://api.openai.com`. Set this if you use a proxy, Azure OpenAI, or an OpenRouter-style gateway. |
| `IVY_AGENT_DEBUG_FOLDER` | No | Path where Ivy agent debug sessions store logs and Langfuse traces (e.g. `D:\Temp\ivy-agent`). Used by `IvyAgentDebug.ps1`. |

### Installing the VS Code Extension

The extension lives at:

```
D:\Repos\_Personal\Scripts\AF2\.vscode-extensions\ivy-plans
```

**Simplest method** — create a symlink:

```cmd
mklink /D "%USERPROFILE%\.vscode\extensions\ivy-plans" "D:\Repos\_Personal\Scripts\AF2\.vscode-extensions\ivy-plans"
```

**Alternative**: Copy the folder directly into `%USERPROFILE%\.vscode\extensions\ivy-plans`.

After installing, reload VS Code. The extension activates automatically.

### Plans Directory

The scripts auto-create most subdirectories, but here's the full structure:

```
D:\Repos\_Ivy\.plans\
  .counter         — Auto-incrementing plan ID counter
  approved/        — Plans ready for BuildApproved to execute
  completed/       — Successfully executed plans
  failed/          — Plans that failed execution
  history/         — Previous versions of split/updated plans
  logs/            — Execution logs from BuildApproved
  prompts/         — Saved prompts used to generate plans
  review/          — Review checklists created by BuildApproved
  skipped/         — Plans deliberately skipped
  updating/        — Plans currently being updated by Claude
```

---

## 3. The VS Code Extension (ivy-plans)

The extension adds 5 commands to VS Code, available via the Command Palette, context menu (right-click `.md` files in Explorer), and keyboard shortcuts:

| Command | Shortcut | Description |
|---|---|---|
| **Ivy: Make Plan** | `Ctrl+Alt+M` | Opens Notepad for you to type a task description, then runs `MakePlan.ps1` to generate a plan file using Claude. |
| **Ivy: Approve Plan** | `Ctrl+Alt+A` | Saves and closes the file, then moves it to the `approved/` subdirectory. `BuildApproved.ps1` picks it up from there. |
| **Ivy: Update Plan** | Context menu | Saves the file, then runs `UpdatePlan.ps1` — add `>>` comments to a plan and have Claude rewrite it incorporating your feedback. |
| **Ivy: Split Plan** | Context menu | Runs `SplitPlan.ps1` to break a multi-issue plan into separate plan files, one issue per file. |
| **Ivy: Skip Plan** | Context menu | Moves the plan to `skipped/` — for plans you want to defer. |

---

## 4. The Applications

### Plan Lifecycle

#### `MakePlan.ps1`

Firmware-based agent that generates plan files. Opens Notepad (or accepts args) for your task description, researches the codebase, searches GitHub issues for duplicates, and produces a numbered plan file in `.plans/`.

- Plan IDs are auto-incremented via a lock-file counter to avoid collisions when multiple plans are generated concurrently.
- Filename format: `XXX-<RepoName>-<Title>.md`
- Supports `[NNN]` references in the first line to pull in related plans as context.
- READ-ONLY for source code — only writes to `.plans/`
- Includes special checklists for new widgets (6 required artifacts)
- Can trigger visual verification via `IvyFeatureTester.ps1`

#### `UpdatePlan.ps1 -PlanPath <path>`

Firmware-based agent. Edit an existing plan by adding `>>` comments. Claude rewrites incorporating your feedback.

- Previous version saved to `history/`
- Version suffix (`-v2`, `-v3`, ...)
- Validates completeness, retries up to 3 times

#### `SplitPlan.ps1 -PlanPath <path>`

Firmware-based agent. Splits a multi-issue plan into separate single-issue plan files.

- Reserves a batch of 5 IDs upfront
- Add `>>` annotations to guide the split
- Requires at least 2 output plans

#### `BuildApproved.ps1 [-PollInterval <int>]`

The execution engine (standalone script, not firmware-based). Polls `.plans/approved/` for `.md` files every N seconds (default: 3).

Groups plans into **queues** by the second segment of the filename:

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
- Shows a **live TUI dashboard** with running/pending/completed status

#### `ExecutePlan.ps1 -PlanFile <path>`

Execute a single plan file directly (outside of BuildApproved). Parses the filename to determine the queue/working directory and runs Claude with the plan content.

#### `CleanPlans.ps1`

Wipes all files from `completed/`, `failed/`, `history/`, `logs/`, `prompts/`, and `skipped/`.

### Git & PR Agents

#### `CreateCommit.ps1`

Firmware-based agent. Stages all changes, generates a conventional-commit message, and commits.

- Args: `-Push` to also push, `-NoVerify` to skip hooks

#### `CreatePullRequest.ps1`

Firmware-based agent. Creates a PR from unpushed commits — generates branch name, title, body, creates branch, pushes, and opens the PR.

#### `CreateIssue.ps1`

Firmware-based agent. Creates a GitHub issue from a description. Runs from any repo directory, auto-detects the GitHub remote.

#### `MakePrs.ps1`

Firmware-based agent. Analyzes unpushed commits across **all** Ivy repositories and creates logical pull requests:

1. Checks for uncommitted changes across repos
2. Gathers all unpushed commits
3. Fetches open GitHub issues across repos
4. Smart-matches commits to issues (explicit references → keyword/path matching → feature grouping)
5. Presents a plan for user approval
6. Cherry-picks commits to PR branches and creates PRs via `gh`

Three confidence levels for commit-to-issue matching:
- **Explicit** (score 100): commit message references `#123`, `Fixes #123`, etc.
- **Smart match** (score 40-100): keyword, file path, label, and title similarity scoring
- **Feature-based**: unmatched commits grouped by file path or keyword similarity

#### `ReviewCommits.ps1`

Interactive TUI (standalone script) for reviewing unpushed commits across all Ivy repos. For each commit:

- **Number**: Open a specific file's diff in VS Code
- **a**: Step through all diffs
- **o**: Open all source files in VS Code
- **m**: Launch `MakePlan` to create improvement plans from the commit
- **s**: Show full commit summary

#### `Sync.ps1`

Firmware-based agent. Synchronizes all repositories:

1. Commits any local changes
2. Pulls from origin
3. Resolves merge conflicts
4. Builds core solutions (with `-NoBuild` flag to skip)
5. Pushes to origin

### Testing & Review Agents

#### `IvyFeatureTester.ps1`

Firmware-based agent. Tests a new Ivy Framework feature end-to-end:

1. Parses feature spec from args
2. Researches the feature in source code, docs, and recent plans
3. Creates a temp project (`D:\Temp\IvyFeatureTester\<yyyy-MM-dd>\`) with demo apps
4. Creates Playwright tests with screenshots
5. Runs tests with up to 10 fix rounds
6. Produces visual quality and feature verification reports

#### `IvyAgentDebug.ps1`

Firmware-based agent. Debugs Ivy agent sessions by analyzing Langfuse traces for hallucinations, missing FAQ entries, and process improvements.

#### `IvyAgentReviewBuild.ps1` / `IvyAgentReviewLangfuse.ps1` / `IvyAgentReviewSpec.ps1` / `IvyAgentReviewTests.ps1`

Firmware-based review agents for different aspects of the Ivy agent.

### Infrastructure Scripts

#### `EnsureLatestIvyFramework.ps1`

Pulls the latest Ivy Framework, builds the frontend (npm), regenerates docs, and builds the .NET solution.

---

## 5. Making It Your Own

### Step 1: Understand the Pattern

The key insight is that each agent is just **a prompt + a folder**. The PowerShell launcher is boilerplate — the real intelligence is in `Program.md`.

### Step 2: Set Up the Infrastructure

1. Copy the `.shared/` folder — this is the firmware and utilities
2. Edit `.shared/Repos.md` with your repository paths
3. Edit `.shared/Paths.md` with your project structure

### Step 3: Create Your First Application

```powershell
# 1. Create the launcher (copy any existing .ps1)
Copy-Item MakePlan.ps1 MyTool.ps1

# 2. Create the application folder
mkdir MyTool

# 3. Write your Program.md
notepad MyTool/Program.md
```

Your `Program.md` is where you describe what the agent should do. Write it like you're instructing a junior developer — include all the context, paths, and rules they'd need.

### Step 4: Run It

```powershell
.\MyTool.ps1 "your task description here"
```

The agent will:
- Read your Program.md
- Execute the task
- Log the results
- Reflect and potentially improve its own Program.md

### Step 5: Iterate

- Review logs to see how the agent performed
- Use `-Feedback` flag to give improvement feedback: `.\MyTool.ps1 -Feedback "stop doing X, start doing Y"`
- The agent improves over time through reflection and feedback

### Adapting for Non-Ivy Projects

The plan pipeline (MakePlan → BuildApproved) is project-agnostic. To adapt:

1. Update `BuildApproved.ps1` queue mappings to your repos
2. Update `ExecutePlan.ps1` queue mappings similarly
3. Rewrite `MakePlan/Program.md` with your project's context and conventions
4. Update `.shared/Paths.md` and `.shared/Repos.md`

The firmware, VS Code extension, and agent pattern work for any codebase.

---

## 6. Tips

- **Start small**: use `MakePlan` for a single task, review the plan, approve it, and watch `BuildApproved` execute it. Get comfortable before batching.
- **Use `>>` comments** in `UpdatePlan` to iteratively refine plans. The version history is kept so you can always go back.
- **`SplitPlan`** is great for when you brainstorm a big feature and want to break it into atomic, independently-executable chunks.
- **Parallel queues** in `BuildApproved` let you work on multiple repos at once. Each repo gets its own sequential queue to avoid merge conflicts.
- **`ReviewCommits`** gives you a fast way to audit AI-generated changes before pushing. Use the `m` option to create follow-up plans from commits.
- **The plan IS the permission boundary**: `--dangerously-skip-permissions` means Claude runs with full file system access. Review plans carefully before approving.
- **Agents improve over time**: Check the Memory/ folder of any agent to see what it has learned. Prune outdated learnings.
- **Use `-Feedback`** to teach agents: `.\MakePlan.ps1 -Feedback "plans are too verbose, keep them shorter"`
- **Logs are your audit trail**: Every execution is logged with sequential numbering. Review them to understand agent behavior.
