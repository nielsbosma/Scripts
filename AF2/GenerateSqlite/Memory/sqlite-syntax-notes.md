# SQLite Syntax Notes

## Partial Indexes

SQLite does NOT support `CREATE PARTIAL INDEX`. The correct syntax is:

```sql
CREATE INDEX idx_name ON table(column) WHERE condition;
```

The `WHERE` clause makes it a partial index. No `PARTIAL` keyword.

## Generated Columns

SQLite generated columns (both STORED and VIRTUAL) cannot use non-deterministic functions like `date('now')`, `datetime('now')`, or `julianday('now')`. These will fail with: `Runtime error: non-deterministic use of date() in a generated column`.

SQLite also prohibits **subqueries** in generated column expressions. You cannot use `SELECT`, `json_group_array()`, or any subquery inside a generated column definition. This will fail with: `subqueries prohibited in generated columns`.

**Workaround:** Compute non-deterministic, subquery-based, or aggregate values in **views** instead of generated columns. Generated columns are fine for simple deterministic expressions like `first_name || ' ' || last_name`, `amount - paid_amount`, or `COALESCE(a, 0) + COALESCE(b, 0)`.

## sqlite3 CLI availability

sqlite3 is not pre-installed on this Windows environment. It was downloaded to `/c/sqlite/sqlite3.exe` from the SQLite download page (sqlite-tools-win-x64). If it goes missing, re-download.
