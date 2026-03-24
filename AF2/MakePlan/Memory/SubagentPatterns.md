# Subagent Patterns for Ivy-Agent

Based on Simon Willison's guide on agentic engineering patterns (2026-03-23).

## Core Problem: Context Window Management

**Primary limitation**: LLMs have context limits (~200K-1M tokens). Even with large windows, quality degrades at higher token counts.

**Solution**: Subagents provide fresh context windows for specific subtasks without consuming the parent agent's valuable top-level context.

## How Subagents Work

- **Fresh context**: Each subagent starts with a clean slate, new prompt
- **Standard tool pattern**: Parent dispatches subagent like any other tool, waits for response
- **Context preservation**: Keeps parent agent's context lean by offloading token-heavy operations

## Usage Patterns

### 1. Sequential Subagents (Most Common)

Parent agent pauses while subagent executes. Best for:
- **Exploration/Research**: "Find the code that implements X in this Django blog"
- **Token-heavy analysis**: Deep dives into large codebases
- **Focused retrieval**: Gather specific information without polluting parent context

**Ivy-Agent application**: Our Explore subagent (already implemented) follows this pattern.

### 2. Parallel Subagents

Multiple subagents run simultaneously. Best for:
- **Independent multi-file edits**: "Find and update all templates affected by this change"
- **Speed optimization**: Can use faster/cheaper models (e.g., Haiku)
- **No interdependencies**: Each task is self-contained

**Ivy-Agent opportunity**: Multi-file refactoring, batch updates across repositories.

### 3. Specialist Subagents

Customized subagents with specific roles:
- **Code reviewers**: Identify bugs, feature gaps, design weaknesses
- **Test runners**: Hide verbose output, report only failures (valuable for large test suites)
- **Debuggers**: Specialize in reasoning through problems

**Ivy-Agent opportunity**:
- Test runner subagent could handle `dotnet test` output filtering
- Review subagent for PR quality checks
- Debug subagent for Langfuse trace analysis

## Restraint Principle (CRITICAL)

**Don't overuse subagents.** The guide emphasizes: "While it can be tempting to go overboard breaking up tasks across dozens of different specialist subagents, it's important to remember that the main value of subagents is in preserving that valuable root context and managing token-heavy operations."

**When to use main agent instead**:
- Token budget allows full execution in parent context
- Task requires continuous reasoning across steps
- Debugging and review within token limits

**When to use subagents**:
- Token-heavy operations (large file reads, verbose test output)
- Fresh context benefits reasoning (exploratory research)
- Parallel execution speeds up independent tasks
- Specialist roles improve focus (dedicated debugging)

## Implementation Checklist

When considering subagents for Ivy-Agent:

1. ✓ **Is this token-heavy?** (e.g., reading many files, processing verbose output)
2. ✓ **Does fresh context help?** (e.g., exploration without prior assumptions)
3. ✓ **Can tasks run in parallel?** (e.g., independent file updates)
4. ✓ **Would specialization help?** (e.g., focused debugging vs. general coding)

If NO to all → use main agent.

## Platform Support

Multiple platforms support subagents: OpenAI Codex, Claude, Gemini CLI, Mistral Vibe, OpenCode, VS Code, Cursor.

## Ivy-Agent Current State

**Already implemented**:
- Explore subagent (sequential pattern for codebase research)

**Opportunities**:
- Parallel subagents for multi-file operations
- Test runner subagent (hide verbose `dotnet test` output)
- Review subagent (code quality checks before PR)
- Debug subagent (Langfuse trace analysis)

## Key Takeaway

Subagents are for **context management**, not task distribution. Use sparingly when token efficiency matters, not as default architecture.
