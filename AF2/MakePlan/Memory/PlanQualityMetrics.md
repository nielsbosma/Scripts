# Plan Quality Metrics

Based on WebCode evaluation framework (Exa Labs, 2026), adapted for implementation plan generation.

## Core Principle: Separation of Concerns

**Separate evaluation of**:
1. **Retrieval Quality** - Did we read the right source files during research?
2. **Synthesis Quality** - Is the plan complete and actionable?

This prevents conflating research failures (missed critical files) with planning failures (incomplete steps).

## Discriminative vs Generative Evaluation

**Discriminative**: Does the plan *contain* all necessary information to succeed?
**Generative**: Did execution of the plan succeed?

A plan can contain everything needed but fail due to execution issues. Focus evaluation on content completeness, not just outcome.

## Multi-Dimensional Plan Assessment

Evaluate plans across:

### 1. Groundedness
- All file references use markdown links: `[FileName.cs](file:///path)` (enforced in Program.md)
- References point to actual files, not hallucinated paths
- Solution based on actual codebase patterns, not general knowledge

### 2. Completeness
- All implementation steps present (Problem → Solution → Tests → Finish)
- No gaps requiring human inference
- Related plans referenced with `[ID]` syntax

### 3. Actionability
- Another agent could execute without asking clarifying questions
- Commands are copy-pasteable
- Test cases specify exact class/method names and assertions

### 4. Test Coverage
- Automated tests specified (not just "build and verify manually")
- Regression tests for bug fixes
- Commands to run tests included
- Verification steps in Tests section, not after Finish (see VerificationSteps.md)

## Retrieval Quality Tracking

**Current gap**: We don't log which files were read during research or whether they were sufficient.

**Proposed logging** (for future implementation):
- Files read during research phase
- Search patterns used (glob/grep queries)
- Whether research required iteration (sign of unclear requirements or wrong initial files)
- Files that should have been consulted but weren't

This would help identify patterns:
- Do we repeatedly miss certain file types?
- Do we search too broadly/narrowly?
- Are there common retrieval blind spots?

## Application

When reviewing plans before execution:
1. ✓ Groundedness check: all `[name](file:///...)` links valid?
2. ✓ Completeness check: can agent execute without questions?
3. ✓ Test check: automated tests with specific assertions?
4. ✓ Actionability check: commands copy-pasteable?

When analyzing plan failures:
- Was information missing from plan? (synthesis failure)
- Or was correct information present but execution failed? (implementation failure)
