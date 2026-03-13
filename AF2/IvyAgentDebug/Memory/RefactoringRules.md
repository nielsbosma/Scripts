# Refactoring Rules Reference

## Location

- **Service**: `D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent\CSharp\IvyCSharpRefactoringService.cs`
- **Extensions**: `D:\Repos\_Ivy\Ivy-Agent\Ivy.Agent\CSharp\Extensions\` (21 files)
- **Docs**: `D:\Repos\_Ivy\Ivy-Framework\src\.releases\Refactors\` (by version)

## How They Work

Rules are `record Rule(string RuleName, Func<bool> Predicate, Func<CSharpCodeRefactoring, Task<bool>> Apply)`.

Triggered on every `WriteFileMessage` for `.cs` files. Rules run sequentially on a Roslyn syntax tree. Applied rules are emitted as telemetry.

Predicates can restrict rules (e.g., `!message.IsEdit` = new files only).

## Rule Categories

### Enum Replacements (Invalid Values → Valid)

LLMs hallucinate enum values that don't exist. Rules auto-fix:

| Pattern | Fix |
|---------|-----|
| `Icons.InvalidName` | LLM-matched valid icon (via `EnumMatchAgent`) |
| `Colors.Slate500` | Strip digits → `Colors.Slate` |
| `ButtonVariant.Default` | → `ButtonVariant.Primary` |
| `BadgeVariant.Default` | → `BadgeVariant.Primary` |
| `CalloutVariant.Default` | → `CalloutVariant.Info` |
| `TextVariant.Default` | → `TextVariant.Literal` |
| `CardHoverVariant.Default` | → `CardHoverVariant.None` |
| `TabsVariant.Default` | → `TabsVariant.Content` |
| `SelectInputVariant.Default` | → `SelectInputVariant.Select` |
| `TextInputVariant.Default` | → `TextInputVariant.Text` |
| `BoolInputVariant.Default` | → `BoolInputVariant.Checkbox` |
| `ColorInputVariant.Default` | → `ColorInputVariant.Text` |
| `DateTimeInputVariant.Default` | → `DateTimeInputVariant.Date` |
| `FileInputVariant.Default` | → `FileInputVariant.Drop` |
| `NumberInputVariant.Default` | → `NumberInputVariant.Number` |
| `FeedbackInputVariant.Default` | → `FeedbackInputVariant.Stars` |
| `ColorInputVariants` | → `ColorInputVariant` (type rename) |
| `DateTimeInputVariants` | → `DateTimeInputVariant` (type rename) |
| `BoolInputVariants` | → `BoolInputVariant` (type rename) |
| `SelectInputVariants` | → `SelectInputVariant` (type rename) |
| `TextInputVariants` | → `TextInputVariant` (type rename) |
| `NumberInputVariants` | → `NumberInputVariant` (type rename) |
| `FileInputVariants` | → `FileInputVariant` (type rename) |
| `FeedbackInputVariants` | → `FeedbackInputVariant` (type rename) |
| `Languages.PlainText/Plain/Http` | → `Languages.Text` |

### Method Renames (Old API → New)

| Old | New |
|-----|-----|
| `card.Body()` | `card.Content()` |
| `card.Subtitle()` | `card.Description()` |
| `card.Child()` | `card.Content()` |
| `refreshToken.Trigger()` | `refreshToken.Refresh()` |
| `button.Tertiary()` | `button.Ghost()` |
| `textInput.ReadOnly()` | `textInput.Disabled()` |
| `state.ToCheckboxInput()` | `state.ToBoolInput()` |
| `Size.Pixels()` | `Size.Px()` |

### EF Core / LINQ Fixes

| Rule | Prevents |
|------|----------|
| `AddMissingToListAsync` | Adds `.ToListAsync()` to incomplete EF queries |
| `RewriteSplitLastToSubstring` | `Split().Last()` → `Substring(IndexOf() + 1)` |
| `RewriteSplitIndexerToSubstring` | `Split()[1]` → `Substring(IndexOf() + 1)` |

### Type System Fixes

| Rule | Prevents |
|------|----------|
| `AddNullableCastInTernary` | CS0173: `cond ? val : null` → `(type?)val` |
| `FixDuplicateAnonymousTypeProperties` | `new { a.Name, b.Name }` → `new { a.Name, BName = b.Name }` |

### Syntax / Cleanup (new files only)

| Rule | What |
|------|------|
| `RemoveComments` | Strips all comments |
| `ConvertToFileScopedNamespace` | Block → file-scoped namespace |
| `RemoveInvalidIvyUsings` | Removes hallucinated Ivy.* namespaces (runs on ALL files, predicate `() => true`). **Known issue (Plan 496)**: list includes valid namespaces `Ivy.Shared` and `Ivy.Views` which are needed by external widget projects that reference Ivy via NuGet (no global usings). Previously also included `Ivy.Core.*` (fixed by Plan 431). |

## When to Suggest a New Rule

A new refactoring rule is appropriate when:
- The same hallucination pattern appears across multiple sessions
- The fix is mechanical (AST transformation, not semantic)
- A Roslyn syntax walker can reliably detect the pattern
- The fix doesn't require understanding the code's intent

Not appropriate when:
- The issue is a one-off mistake
- The fix requires semantic understanding (use docs/FAQ instead)
- The wrong API usage is ambiguous (multiple valid replacements)
