# SQLite Syntax Notes

## Partial Indexes

SQLite does NOT support `CREATE PARTIAL INDEX`. The correct syntax is:

```sql
CREATE INDEX idx_name ON table(column) WHERE condition;
```

The `WHERE` clause makes it a partial index. No `PARTIAL` keyword.

## sqlite3 CLI availability

sqlite3 is not pre-installed on this Windows environment. It was downloaded to `/c/sqlite/sqlite3.exe` from the SQLite download page (sqlite-tools-win-x64). If it goes missing, re-download.
