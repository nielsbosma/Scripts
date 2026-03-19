# Hallucinations.md Reranking Rule

When modifying `Docs/05_Other/Hallucinations.md`, rerank all `##` sections by descending frequency after applying the changes.

## Ranking rules

- Count each unique UUID in "Found In" as 1
- `(multiple sessions)` = 3
- `(session not yet recorded)` = 1
- Entries with "appeared in ALL sub-tasks" get +2 bonus
- Entries with no "Found In" section = 0
- Ties: preserve existing relative order (stable sort)
- "now supported" entries always go to the bottom regardless of count
