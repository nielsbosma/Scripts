# GenerateSqlite

Generate a SQLite database from a natural language description.

## Context

The firmware header contains:
- **Args** — natural language description of the database to generate
- **WorkDir** — directory where output files should be created

## Execution Steps

### 1. Parse Args

Extract the database description from Args. This is a natural language description like "an e-commerce database with users, products, orders, and reviews".

### 2. Generate SQL Script

Based on the description, generate a single `.sql` script that creates a complete database. The schema should demonstrate a wide range of SQLite features:

**Schema features to include where appropriate:**
- Normalized tables with appropriate columns, types, primary keys, and foreign keys
- All standard SQLite types (`INTEGER`, `TEXT`, `REAL`, `BLOB`, `NUMERIC`)
- `UNIQUE` constraints, `CHECK` constraints, and `NOT NULL` where appropriate
- Composite primary keys where the domain warrants them
- `ON DELETE CASCADE` / `ON UPDATE CASCADE` on foreign keys
- Indexes on foreign keys and commonly queried columns, including composite indexes
- Partial indexes (e.g. `CREATE INDEX ... WHERE status = 'active'`)
- Views for common queries or aggregations
- Triggers for auto-updating `updated_at` timestamps
- `DEFAULT` values using expressions (e.g. `DEFAULT (datetime('now'))`)
- `WITHOUT ROWID` tables where applicable (e.g. junction/mapping tables with composite PKs)
- `STRICT` tables where type enforcement is desired
- Generated/computed columns where useful (e.g. `full_name` from `first_name || ' ' || last_name`)
- `COLLATE NOCASE` on text columns used for case-insensitive lookups

**Dummy data requirements:**
- Use realistic-looking names, emails, addresses, etc. (not "test1", "test2")
- Respect foreign key relationships (referenced rows must exist)
- Generate 10-50 rows per table (reasonable for exploration)
- Include edge cases: NULL values where nullable, empty strings, boundary dates
- Use CTEs or `INSERT ... SELECT` for some data to showcase query capabilities

Write the SQL script to `<WorkDir>/schema.sql`.

### 3. Create the SQLite File

Execute the SQL using the `sqlite3` CLI:

```bash
sqlite3 "<WorkDir>/output.sqlite" < "<WorkDir>/schema.sql"
```

Before the schema, include:
```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
```

Verify the database by running `SELECT count(*) FROM <table>` for each table.

### 4. Output Summary

Print a summary showing:
- Tables created and row counts
- SQLite features used (list of features exercised in the generated schema)
- The output file path

## Rules

- Use `sqlite3` CLI to create the database
- Generate all SQL as a single `.sql` script first, then pipe to `sqlite3`
- Keep the intermediate `.sql` file in the working directory
- If Args is empty or missing, fail with an error asking for a database description
