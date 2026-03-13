# Extracting Supabase Schemas from Lovable Applications

This document provides comprehensive guidance on detecting and extracting Supabase table schemas from Lovable applications, based on analysis of the Ivy-Web Supabase implementation.

## Overview

Lovable applications typically use Supabase as their backend database. The schema can be stored in multiple locations and formats, each serving different purposes in the development workflow.

## 1. Common Schema Locations

### Primary Locations

#### A. Migration Files (`supabase/migrations/`)
The most authoritative source for schema definitions. Migrations are timestamped SQL files that define incremental database changes.

**Pattern**: `YYYYMMDDHHMMSS_description.sql`

**Example structure**:
```
supabase/
└── migrations/
    ├── 20221215192558_schema.sql          # Initial schema
    ├── 20240319163440_roles-seed.sql      # Data seeding
    ├── 20241007151024_delete-team-account.sql  # RLS policy
    └── 20251210121820_add_billing_sync_tracking.sql  # Schema update
```

**Content types**:
- Initial schema definitions (CREATE TABLE, CREATE TYPE, CREATE FUNCTION)
- Schema alterations (ALTER TABLE ADD COLUMN, CREATE INDEX)
- RLS (Row Level Security) policies (CREATE POLICY)
- Seed data (INSERT statements)
- Triggers and functions (CREATE TRIGGER, CREATE FUNCTION)

#### B. Seed Data (`supabase/seed.sql`)
Contains initial data for development/testing. Includes:
- Webhooks configuration
- Development user accounts
- Default role assignments
- Sample data for testing

#### C. TypeScript Type Definitions
Generated types that mirror the database schema.

**Locations**:
- `lib/database.types.ts` (app-specific)
- `packages/supabase/src/database.types.ts` (shared packages)

**Generation command**:
```bash
supabase gen types typescript --local > ./lib/database.types.ts
```

#### D. Supabase Config (`supabase/config.toml`)
Contains project configuration including:
- API settings (exposed schemas, max_rows)
- Database connection details
- Auth configuration
- Storage limits
- Email templates

### Secondary Locations

#### E. Test Files (`supabase/tests/`)
Database tests that reveal schema structure and constraints:
```
supabase/tests/database/
├── 00000-dbdev.sql
├── 00000-makerkit-helpers.sql
├── account-permissions.test.sql
├── account-slug.test.sql
└── invitations.test.sql
```

## 2. Schema Definition Patterns

### Table Creation Pattern
```sql
-- Standard table with common patterns
CREATE TABLE public.accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  primary_owner_user_id UUID NOT NULL REFERENCES auth.users(id),
  name TEXT NOT NULL,
  slug TEXT UNIQUE,
  email TEXT,
  is_personal_account BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ,
  created_by UUID,
  updated_by UUID,
  picture_url TEXT,
  public_data JSONB DEFAULT '{}'::JSONB
);
```

**Common patterns**:
- UUID primary keys with `gen_random_uuid()`
- Audit fields: `created_at`, `updated_at`, `created_by`, `updated_by`
- Foreign keys to `auth.users` for user references
- JSONB columns for flexible data (`public_data`, `metadata`)
- Boolean flags with defaults

### Enum Types
```sql
CREATE TYPE public.app_permissions AS ENUM(
  'roles.manage',
  'billing.manage',
  'settings.manage',
  'members.manage',
  'invites.manage'
);
```

### Indexes
```sql
CREATE INDEX IF NOT EXISTS idx_accounts_billing_sync
ON public.accounts(billing_synced, billing_sync_attempted_at)
WHERE billing_synced = FALSE;
```

**Index patterns**:
- Partial indexes with WHERE clauses for optimization
- Multi-column indexes for common query patterns
- Unique indexes for constraints

### Row Level Security (RLS)
```sql
CREATE POLICY delete_team_account
    ON public.accounts
    FOR DELETE
    TO authenticated
    USING (
        auth.uid() = primary_owner_user_id
    );
```

**RLS patterns**:
- Policies for SELECT, INSERT, UPDATE, DELETE operations
- User-specific access via `auth.uid()`
- Role-based access control
- Team/organization scoping

### Triggers and Functions
```sql
CREATE TRIGGER "accounts_teardown" AFTER DELETE
ON "public"."accounts" FOR EACH ROW
EXECUTE FUNCTION "supabase_functions"."http_request"(
  'http://host.docker.internal:3000/api/db/webhook',
  'POST',
  '{"Content-Type":"application/json", "X-Supabase-Event-Signature":"WEBHOOKSECRET"}',
  '{}',
  '5000'
);
```

### Comments for Documentation
```sql
COMMENT ON COLUMN public.accounts.billing_synced IS
  'Whether user has been successfully synced with Ivy Billing. FALSE means sync is pending or failed.';
```

## 3. Extracting Schema Information

### Method 1: Parse Migration Files
**Best for**: Complete schema history and evolution

```bash
# Find all migration files
find ./supabase/migrations -name "*.sql" -type f | sort

# Extract table definitions
grep -E "CREATE TABLE|ALTER TABLE" ./supabase/migrations/*.sql

# Extract RLS policies
grep -E "CREATE POLICY|ALTER POLICY" ./supabase/migrations/*.sql
```

### Method 2: Generate TypeScript Types
**Best for**: Current schema structure with type information

```bash
# Local database
supabase gen types typescript --local > database.types.ts

# Remote database
supabase gen types typescript --project-ref <project-ref> > database.types.ts
```

**TypeScript type structure**:
```typescript
export type Database = {
  public: {
    Tables: {
      accounts: {
        Row: { /* column types for SELECT */ }
        Insert: { /* column types for INSERT */ }
        Update: { /* column types for UPDATE */ }
      }
    }
    Views: { /* view definitions */ }
    Functions: { /* function signatures */ }
    Enums: { /* enum types */ }
  }
}
```

### Method 3: Introspect Live Database
**Best for**: Production schema verification

```bash
# Dump schema structure
supabase db dump --local --schema-only > schema.sql

# Dump with data
supabase db dump --local > full-dump.sql
```

### Method 4: Parse Supabase Config
**Best for**: Understanding API exposure and configuration

```toml
[api]
schemas = ["public", "storage", "graphql_public"]
extra_search_path = ["public", "extensions"]
```

## 4. Key Schema Components to Extract

### Tables
- Table names
- Column names and data types
- Primary keys
- Foreign keys and relationships
- Default values
- Constraints (NOT NULL, UNIQUE, CHECK)
- Indexes

### Relationships
```sql
-- Foreign key relationships
account_id UUID REFERENCES public.accounts(id) ON DELETE CASCADE
user_id UUID REFERENCES auth.users(id)
```

**Extraction strategy**:
- Look for `REFERENCES` keyword
- Identify cascade behavior (ON DELETE CASCADE, ON UPDATE CASCADE)
- Map table relationships for entity diagrams

### Security Policies
- Policy names and operations (SELECT, INSERT, UPDATE, DELETE)
- Target roles (authenticated, anon, service_role)
- Policy conditions (USING, WITH CHECK clauses)
- Policy relationships to tables

### Functions and Triggers
- Function signatures and return types
- Trigger events (BEFORE/AFTER, INSERT/UPDATE/DELETE)
- Trigger timing
- Function bodies for business logic

### Enums and Custom Types
```sql
CREATE TYPE public.app_permissions AS ENUM(...);
```

### Extensions
```sql
CREATE EXTENSION IF NOT EXISTS "unaccent" SCHEMA kit;
```

### Schemas
```sql
CREATE SCHEMA IF NOT EXISTS kit;
```

## 5. Schema Evolution Tracking

Migration files are timestamped, allowing you to:

1. **Reconstruct schema at any point**: Apply migrations up to a specific timestamp
2. **Understand changes**: Review migration history to see how schema evolved
3. **Generate diffs**: Compare migrations to understand what changed between versions

## 6. Integration with Client Code

### Supabase Client Instantiation
Look for client creation patterns:

```typescript
import { createClient } from '@supabase/supabase-js'
import type { Database } from './database.types'

const supabase = createClient<Database>(url, key)
```

### Query Patterns
```typescript
// Type-safe queries based on generated types
const { data, error } = await supabase
  .from('accounts')
  .select('*')
  .eq('slug', 'my-account')
```

## 7. Lovable-Specific Considerations

While this research is based on a MakerKit/Supabase template (similar to what Lovable might generate), Lovable applications likely follow similar patterns:

1. **Standard Supabase structure**: `supabase/` directory with migrations and config
2. **Type generation**: TypeScript types generated from schema
3. **RLS policies**: Heavy use of Row Level Security for multi-tenant applications
4. **Auth integration**: Tables frequently reference `auth.users`
5. **Audit trails**: Common pattern of created_at/updated_at/created_by/updated_by fields

### Detection Strategy for Lovable Apps

1. Check for `supabase/` directory in project root
2. Look for `config.toml` to confirm Supabase usage
3. Parse migration files for schema definition
4. Generate or locate TypeScript types
5. Review package.json for `@supabase/supabase-js` dependency
6. Check for RLS policies in migrations

## 8. Tools and Commands

### Supabase CLI Commands
```bash
# Start local Supabase
supabase start

# Stop local Supabase
supabase stop

# Reset database and re-run migrations
supabase db reset

# Run database tests
supabase db test

# Lint migrations
supabase db lint

# Generate types
supabase gen types typescript --local

# Deploy migrations
supabase db push

# Create new migration
supabase migration new <name>
```

### Package.json Scripts
Common script patterns in Lovable/Supabase projects:

```json
{
  "scripts": {
    "supabase:start": "supabase start",
    "supabase:reset": "supabase db reset",
    "supabase:typegen": "supabase gen types typescript --local > lib/database.types.ts",
    "supabase:deploy": "supabase db push"
  }
}
```

## 9. Schema Extraction Algorithm

**Recommended approach for automated extraction**:

```
1. Locate supabase/ directory
2. Parse config.toml for:
   - Project ID
   - Exposed schemas
   - API configuration
3. Read all migration files in order (sorted by timestamp)
4. Extract from each migration:
   - CREATE TABLE statements
   - ALTER TABLE statements
   - CREATE TYPE/ENUM statements
   - CREATE POLICY statements
   - CREATE FUNCTION statements
   - CREATE TRIGGER statements
   - CREATE INDEX statements
   - COMMENT statements
5. Build schema representation:
   - Tables with columns, types, constraints
   - Relationships (foreign keys)
   - Policies (RLS rules)
   - Functions and triggers
   - Enums and custom types
6. Validate against TypeScript types (if available)
7. Generate documentation or schema diagram
```

## 10. Example Schema Artifacts

### Typical Tables in Lovable Apps
Based on the Ivy-Web example, expect tables like:

- `accounts` - Team/organization accounts
- `users` (in auth schema) - User authentication
- `accounts_memberships` - User-account relationships
- `roles` - Role definitions
- `role_permissions` - Permission assignments
- `invitations` - Account invitations
- `subscriptions` - Billing subscriptions
- `billing_customers` - Billing integration
- `orders` / `order_items` - E-commerce if applicable

### Common Patterns
- Multi-tenancy via `account_id` foreign keys
- Soft deletes or cascade deletes
- JSONB columns for flexible metadata
- Timestamp tracking (created_at, updated_at)
- User audit trails (created_by, updated_by)
- UUID primary keys
- RLS policies for data isolation

## Summary

To extract Supabase schemas from Lovable applications:

1. **Primary source**: `supabase/migrations/*.sql` files (ordered by timestamp)
2. **Type definitions**: `lib/database.types.ts` or generated via `supabase gen types`
3. **Configuration**: `supabase/config.toml`
4. **Seed data**: `supabase/seed.sql`
5. **Tests**: `supabase/tests/` (if present)

The schema can be fully reconstructed by parsing migration files in chronological order, extracting all DDL statements, and building a complete picture of tables, columns, relationships, policies, and business logic.
