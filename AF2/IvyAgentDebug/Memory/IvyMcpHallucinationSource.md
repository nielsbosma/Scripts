# IvyMcp as Hallucination Source

When investigating hallucinations in `langfuse-hallucinations.md`, always check the raw IvyQuestion answer JSON to determine if the hallucination originates from **IvyMcp** (the knowledge base service) or from the **LLM agent** itself.

## How to check

1. Find the IvyQuestion event in `langfuse/<trace>/0XX_EVENT__local__IvyQuestion.json`
2. Read `metadata.answer` — does it contain the hallucinated API?
3. If YES → the fix is in IvyMcp knowledge base (create IvyMcp plan)
4. If NO → the LLM invented it (add to Hallucinations.md, consider refactoring rule)

## Known IvyMcp source hallucinations

- **Badge.Color()** — IvyMcp answer shows `.Color(Colors.Success)` (found in 7+ sessions)
- **Expandable one-param constructor + .Child()** — IvyMcp shows `new Expandable("title").Child(content)`

## Why this matters

IvyMcp source hallucinations are MORE impactful than LLM-originated ones because:
- They affect every session that asks the same question
- The agent trusts IvyQuestion answers as authoritative
- Fixing IvyMcp prevents the hallucination at the source vs. relying on build-error recovery
