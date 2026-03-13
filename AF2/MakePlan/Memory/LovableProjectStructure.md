# Lovable Application Structure (Confirmed from Real Repos)

## Tech Stack
- **Build**: Vite + React + TypeScript (SPA, not SSR)
- **UI**: shadcn/ui (Radix primitives) + Tailwind CSS
- **State**: @tanstack/react-query for server state, React useState for local
- **Routing**: react-router-dom with BrowserRouter
- **Forms**: react-hook-form + zod validation
- **Charts**: recharts
- **Icons**: lucide-react
- **Toasts**: sonner + @radix-ui/react-toast
- **Backend**: Supabase (Auth, DB, Edge Functions, Storage, Realtime)

## Standard Project Structure
```
/
  package.json          # name often "vite_react_shadcn_ts"
  index.html            # Vite entry point
  components.json       # shadcn/ui config
  vite.config.ts
  tsconfig.json
  postcss.config.js
  tailwind.config.ts
  eslint.config.js
  .lovable/             # Lovable-specific metadata
  public/
    lovable-uploads/    # User-uploaded assets via Lovable UI
    placeholder.svg
  src/
    App.tsx             # Root component with QueryClient, AuthProvider, Router, Routes
    App.css
    main.tsx
    index.css
    vite-env.d.ts
    components/
      ui/               # shadcn/ui components (auto-generated, don't convert)
      [feature]/        # Feature-specific components in subdirs
    pages/              # Route page components (each = a "page")
    hooks/              # Custom hooks (use-mobile, use-toast, data fetching)
    lib/
      utils.ts          # cn() helper and utilities
    utils/              # App-specific utilities (optional)
    types/              # TypeScript type definitions (optional)
    integrations/
      supabase/
        client.ts       # Auto-generated: createClient<Database>(URL, KEY)
        types.ts        # Auto-generated: Database type with Tables/Views/Functions/Enums
  supabase/
    config.toml         # project_id + [functions.*] declarations with verify_jwt
    migrations/         # SQL files: YYYYMMDDHHMMSS_<uuid-or-desc>.sql
    seed.sql            # Optional seed data
    functions/          # Edge Functions (optional)
      <function-name>/
        index.ts        # Deno TS: import { serve } from "https://deno.land/std@.../http/server.ts"
```

## Key Patterns

### Supabase Client (auto-generated)
```typescript
// src/integrations/supabase/client.ts
import { createClient } from '@supabase/supabase-js';
import type { Database } from './types';
const SUPABASE_URL = "https://<project-ref>.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "<anon-key>";
export const supabase = createClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { storage: localStorage, persistSession: true, autoRefreshToken: true }
});
```

### Database Types (auto-generated)
```typescript
// src/integrations/supabase/types.ts - THE BEST source for schema extraction
export type Database = {
  public: {
    Tables: {
      <table_name>: {
        Row: { /* all columns with TS types */ }
        Insert: { /* required + optional columns */ }
        Update: { /* all optional columns */ }
        Relationships: []
      }
    }
    Views: { ... }
    Functions: { ... }
    Enums: { ... }
  }
}
```

### Edge Functions (Deno runtime)
```typescript
// supabase/functions/<name>/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
serve(async (req) => {
  // CORS handling (common pattern)
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  // Access secrets via Deno.env.get("SECRET_NAME")
  // Return JSON responses
  return new Response(JSON.stringify(data), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
});
```

### Edge Function Config
```toml
# supabase/config.toml
project_id = "<project-ref>"
[functions.<function-name>]
verify_jwt = false  # or true
```

### App.tsx Routing Pattern
```tsx
<QueryClientProvider client={queryClient}>
  <AuthProvider>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<Landing />} />
          <Route path="/login" element={<Auth />} />
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="*" element={<NotFound />} />
        </Routes>
      </BrowserRouter>
    </TooltipProvider>
  </AuthProvider>
</QueryClientProvider>
```

### Migration Files
- Pattern: `YYYYMMDDHHMMSS_<uuid-or-description>.sql`
- Lovable uses UUID-style names: `20250704024750-95df3f63-9d74-4101-8189-3e7a386045ab.sql`
- Contains: CREATE TABLE, RLS policies, triggers, functions, indexes
- Common patterns: UUID PKs, auth.users FKs, created_at/updated_at, JSONB columns

## Conversion Workflow Exists
Plan 511 creates `Workflows/Conversion/Lovable/` with:
- LovableConversionWorkflow.workflow (main orchestration)
- LovableResearcherWorkflow.workflow (hidden researcher)
- References/ (component mapping docs)

## Lovable-Specific Identifiers
- `public/lovable-uploads/` directory
- `.lovable/` directory with `plan.md`
- `lovable-tagger` in devDependencies
- `"name": "vite_react_shadcn_ts"` in package.json (common default)
- Comments like `// ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE`
- `// This file is automatically generated. Do not edit it directly.` in supabase client
