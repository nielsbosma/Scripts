# Ivy Framework UI Component Patterns

The build agent frequently generates incorrect Ivy UI code. This document captures the correct patterns.

## CRITICAL: Text is a Static Class

**WRONG:** `new Text("content")` — Text is static, cannot be instantiated.
**RIGHT:** `Text.H1("title")`, `Text.P("content")`, `Text.Muted("hint")`, `Text.Danger("error")`, `Text.Strong("bold")`

Chainable: `Text.H2("Title").Bold().Italic().Muted()`

## CRITICAL: Layout, not StackLayout

**WRONG:** `new StackLayout { child1, child2 }` — StackLayout requires constructor args and doesn't support collection initializer.
**RIGHT:** `Layout.Vertical()` or `Layout.Horizontal()` with pipe operator:

```csharp
Layout.Vertical()
    | Text.H2("Title")
    | Text.Muted("Description")
    | (Layout.Horizontal()
        | inputWidget
        | new Button("Go", handler))
```

Also: `Layout.Vertical(child1, child2, child3)` with varargs.
Also: `Layout.Grid().Columns(3)`.

## CRITICAL: TextInput from State

**WRONG:** `new TextInput(value, callback)` — TextInput doesn't have this constructor.
**RIGHT:** Create from IState via extension methods:

```csharp
var query = UseState("");
query.ToTextInput().Placeholder("Enter search...")
```

Variants: `.ToTextareaInput()`, `.ToPasswordInput()`, `.ToSearchInput()`, `.ToEmailInput()`

## Card Pattern

**WRONG:** `new Card { child1, child2 }` — Card doesn't support collection initializer.
**RIGHT:**

```csharp
new Card(content: Layout.Vertical() | Text.P("body"))
    .Title("Card Title")
    .Header(titleObj, descObj, iconObj)
    .Footer(footerObj)
```

## Button Pattern

```csharp
new Button("Label", (Event<Button> e) => { ... }).Icon(Icons.Search)
```

## Conditional Rendering

Use switch expressions for complex conditional UI:

```csharp
object? section = (submitted, loading, error, results) switch
{
    (null, _, _, _) => null,
    (_, true, _, _) => Text.Muted("Loading..."),
    (_, _, string err, _) => Text.Danger(err),
    (_, _, _, { Length: 0 }) => Text.Muted("No results."),
    (_, _, _, SomeType[] items) => Layout.Vertical(items.Select(...).ToArray()),
    _ => null
};
```

## Table Pattern

```csharp
items.ToTable()
    .Header((ItemType r) => r.Name, "Column Title")
```
