# Lovable (lovable.dev) Application Structure - Research Notes

Last updated: 2026-03-13

## 1. Project Structure

A typical Lovable-generated app follows this standardized structure:

```
project-root/
├── public/
│   ├── favicon.ico
│   ├── placeholder.svg
│   └── robots.txt
├── src/
│   ├── assets/                    # Static assets (images, etc.)
│   ├── components/
│   │   ├── ui/                    # shadcn/ui components (copied into project)
│   │   │   ├── button.tsx
│   │   │   ├── card.tsx
│   │   │   ├── dialog.tsx
│   │   │   ├── form.tsx
│   │   │   ├── input.tsx
│   │   │   ├── toast.tsx
│   │   │   ├── toaster.tsx
│   │   │   ├── sonner.tsx
│   │   │   ├── use-toast.ts
│   │   │   └── ... (40+ Radix UI based components)
│   │   └── [AppSpecificComponents].tsx
│   ├── hooks/
│   │   ├── use-mobile.tsx
│   │   ├── use-toast.ts
│   │   └── [custom hooks].tsx
│   ├── integrations/
│   │   └── supabase/
│   │       ├── client.ts          # Auto-generated Supabase client
│   │       ├── types.ts           # Auto-generated TypeScript types from DB schema
│   │       └── api.ts             # (optional) Typed API wrapper functions
│   ├── lib/
│   │   ├── utils.ts               # Utility functions (cn() for classnames)
│   │   └── [other utils].ts
│   ├── pages/
│   │   ├── Index.tsx              # Home page
│   │   ├── NotFound.tsx           # 404 catch-all
│   │   ├── Auth.tsx               # Auth page (if auth enabled)
│   │   └── [OtherPages].tsx
│   ├── App.tsx                    # Root component with routing + providers
│   ├── App.css
│   ├── main.tsx                   # Entry point (renders <App />)
│   ├── index.css                  # Global styles + Tailwind directives
│   └── vite-env.d.ts
├── supabase/                      # Only present if Supabase is connected
│   ├── config.toml                # Supabase project config + function declarations
│   ├── functions/
│   │   └── [function-name]/
│   │       └── index.ts           # Each function in its own directory
│   └── migrations/
│       └── [timestamp]_[uuid].sql # Timestamped SQL migration files
├── .env                           # Environment variables (VITE_SUPABASE_URL, etc.)
├── components.json                # shadcn/ui configuration
├── eslint.config.js
├── index.html                     # HTML entry point
├── package.json
├── package-lock.json
├── postcss.config.js
├── tailwind.config.ts
├── tsconfig.json
├── tsconfig.app.json
├── tsconfig.node.json
└── vite.config.ts
```

## 2. Supabase Edge Functions

### Location and Structure
Edge functions live in `supabase/functions/`. Each function gets its own directory with an `index.ts` entry point:

```
supabase/
├── config.toml
├── functions/
│   ├── my-function-a/
│   │   └── index.ts
│   ├── my-function-b/
│   │   └── index.ts
│   └── my-function-c/
│       └── index.ts
└── migrations/
```

### config.toml
The `supabase/config.toml` is the **source of truth** for function persistence. Every function must be explicitly declared here or it risks being dropped during redeployment:

```toml
project_id = "your-project-ref"

[functions.my-function-a]
verify_jwt = false         # Public endpoint (webhooks, etc.)

[functions.my-function-b]
verify_jwt = true          # Protected endpoint (requires auth)
```

### Edge Function Pattern
Functions are Deno-based TypeScript using `serve()` from Deno standard library:

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { param1, param2 } = await req.json();

    // Access secrets via Deno.env
    const API_KEY = Deno.env.get("SOME_API_KEY");

    // ... business logic ...

    return new Response(
      JSON.stringify({ result: "data" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
```

### Frontend Invocation of Edge Functions
From the frontend, edge functions are called via `supabase.functions.invoke()`:

```typescript
const { data, error } = await supabase.functions.invoke('function-name', {
  body: { param1: 'value1', param2: 'value2' }
});
```

### AI Gateway
Lovable provides an AI gateway at `https://ai.gateway.lovable.dev/v1/chat/completions` that edge functions can use with a `LOVABLE_API_KEY` environment variable.

## 3. Database Schema and Migrations

### Migration Files
Migrations are stored in `supabase/migrations/` with timestamped filenames:
- Format: `[YYYYMMDDHHMMSS]_[uuid].sql`
- Example: `20251002145236_4cccc617-5fe7-4a8f-8b24-db61386462a1.sql`

Lovable generates these SQL files based on natural language prompts. They contain standard PostgreSQL DDL including:
- Table creation with proper types
- Row Level Security (RLS) policies
- Triggers and functions (e.g., auto-create profile on signup)
- Foreign key relationships

### Auto-Generated Types
`src/integrations/supabase/types.ts` is **automatically generated** from the database schema. It exports a `Database` type with full Row/Insert/Update types for every table. This file should not be edited manually.

### Schema Extraction
To get the full schema from a Lovable app:
1. Read the migration files in `supabase/migrations/` (chronological order)
2. Read `src/integrations/supabase/types.ts` for the TypeScript representation
3. Access the Supabase dashboard SQL Editor for the live schema

## 4. Frontend Stack

| Layer | Technology |
|-------|-----------|
| Build Tool | **Vite** (with `@vitejs/plugin-react-swc`) |
| Language | **TypeScript** |
| Framework | **React 18** |
| UI Components | **shadcn/ui** (copied into `src/components/ui/`) |
| Styling | **Tailwind CSS 3** with `tailwindcss-animate` |
| Component Primitives | **Radix UI** (used by shadcn/ui) |
| Icons | **Lucide React** |
| Forms | **React Hook Form** + **Zod** validation |
| Toasts | **Sonner** + shadcn toast |
| Charts | **Recharts** |
| Date Handling | **date-fns** |
| Class Utilities | **clsx**, **tailwind-merge**, **class-variance-authority** |

### Lovable-Specific
- `lovable-tagger` - Dev dependency that tags components for Lovable's visual editor (only active in development mode)

### vite.config.ts Pattern
```typescript
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";
import { componentTagger } from "lovable-tagger";

export default defineConfig(({ mode }) => ({
  server: { host: "::", port: 8080 },
  plugins: [react(), mode === "development" && componentTagger()].filter(Boolean),
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
}));
```

### components.json (shadcn/ui config)
```json
{
  "$schema": "https://ui.shadcn.com/schema.json",
  "style": "default",
  "rsc": false,
  "tsx": true,
  "tailwind": {
    "config": "tailwind.config.ts",
    "css": "src/index.css",
    "baseColor": "slate",
    "cssVariables": true
  },
  "aliases": {
    "components": "@/components",
    "utils": "@/lib/utils",
    "ui": "@/components/ui",
    "lib": "@/lib",
    "hooks": "@/hooks"
  }
}
```

## 5. State Management

Lovable does **not** use a dedicated state management library like Zustand or Redux. Instead:

- **TanStack React Query** (`@tanstack/react-query`) - Used for server state management (data fetching, caching, synchronization). The `QueryClientProvider` wraps the entire app in `App.tsx`.
- **React useState/useEffect** - Used for local component state.
- **Custom hooks** - Business logic is extracted into hooks in `src/hooks/` that combine Supabase calls with local state.
- **Supabase Realtime** - For live data, Lovable can set up frontend subscriptions to table changes via WebSockets.

### Typical Data Flow Pattern
```
Component -> Custom Hook -> supabase client -> Supabase API
                          -> supabase.functions.invoke() -> Edge Function
```

Some projects wrap Supabase calls in a typed API layer (`src/integrations/supabase/api.ts`) using types from the auto-generated `types.ts`.

## 6. Routing

- **React Router DOM v6** (`react-router-dom ^6.x`)
- Uses `BrowserRouter` by default (some recommend `HashRouter` for Lovable preview compatibility)
- Routes are centralized in `App.tsx` using `<Routes>` and `<Route>` components
- Always includes a `*` catch-all route pointing to `NotFound.tsx`

### App.tsx Routing Pattern
```tsx
import { BrowserRouter, Routes, Route } from "react-router-dom";

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<Index />} />
          <Route path="/auth" element={<Auth />} />
          {/* ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE */}
          <Route path="*" element={<NotFound />} />
        </Routes>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);
```

## 7. Authentication

Lovable uses **Supabase Auth** directly from the frontend:

### Client Setup
The Supabase client in `src/integrations/supabase/client.ts` is auto-generated:
```typescript
import { createClient } from '@supabase/supabase-js';
import type { Database } from './types';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_PUBLISHABLE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

export const supabase = createClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: {
    storage: localStorage,
    persistSession: true,
    autoRefreshToken: true,
  }
});
```

### Auth Patterns
- **Email/Password**: `supabase.auth.signUp()` and `supabase.auth.signInWithPassword()`
- **OAuth**: Social login via Supabase providers (Google, GitHub, etc.)
- **Magic Links**: Passwordless auth
- **Session Management**: `supabase.auth.getSession()` and `supabase.auth.onAuthStateChange()` for reactive auth state
- **Sign Out**: `supabase.auth.signOut()`

### Database-Level Auth
- Auth triggers create user profiles automatically (via PostgreSQL triggers)
- Row Level Security (RLS) policies use `auth.uid()` to restrict data access per user
- RLS is enabled on all tables by default

## 8. API Patterns

Lovable uses a **2-tier architecture** where the browser communicates directly with Supabase:

### Direct Client Calls (most common)
For standard CRUD operations, the frontend uses the Supabase JS client directly:
```typescript
// Read
const { data, error } = await supabase.from("table").select("*");

// Insert
const { error } = await supabase.from("table").insert({ column: "value" });

// Update
const { error } = await supabase.from("table").update({ column: "new_value" }).eq("id", id);

// Delete
const { error } = await supabase.from("table").delete().eq("id", id);
```

Security is enforced via RLS policies at the database level, not in an application server.

### Edge Functions (for complex/secret operations)
Edge functions serve as the API layer when operations require:
- **Secrets/API keys** that cannot be exposed to the browser
- **External API calls** (payment processing, AI services, geocoding)
- **Complex business logic** that should run server-side

Invoked via: `supabase.functions.invoke('function-name', { body: {...} })`

### Typed API Layer (optional pattern)
Some projects add `src/integrations/supabase/api.ts` with typed wrapper functions:
```typescript
import { supabase } from './client';
import type { Database } from './types';

type Profile = Database['public']['Tables']['profiles']['Row'];

export const profileApi = {
  async getProfileByEmail(email: string): Promise<Profile | null> {
    const { data, error } = await supabase
      .from('profiles').select('*').eq('email', email).single();
    if (error && error.code !== 'PGRST116') throw new Error(error.message);
    return data || null;
  },
};
```

## 9. Deployment

### Lovable Cloud (default/recommended)
- Frontend ships as a **static SPA via CDN**
- Backend runs on Lovable-managed Supabase
- Custom domains supported with automatic SSL
- Automatic deployments on every edit
- Preview environments built-in

### External Deployment Options
Lovable apps are standard Vite+React projects deployable anywhere:

| Platform | Method |
|----------|--------|
| **Netlify** | Connect GitHub repo, auto-build |
| **Vercel** | Connect GitHub repo, auto-build |
| **Cloudflare Pages** | Connect GitHub repo |
| **AWS** | S3 + CloudFront, ECS, EKS, Amplify |
| **GCP** | Cloud Storage + CDN, Cloud Run, GKE |
| **Azure** | Static Web Apps, Container Apps, AKS |
| **Self-hosted** | Docker, Kubernetes, VMs with Nginx |

### Build Commands
```json
{
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "build:dev": "vite build --mode development",
    "preview": "vite preview"
  }
}
```

## 10. GitHub Integration

### Sync Behavior
- **Two-way sync**: Edits in Lovable appear in GitHub, and changes pushed to the default branch (`main`) sync back to Lovable
- **Single source of truth**: When connected, GitHub is the canonical source
- **Automatic commits**: Changes made in Lovable's editor are committed automatically
- Lovable installs a **GitHub App** for repository access

### Repository Structure
The GitHub repo is a complete, standard Vite+React project. The exact same structure as described in Section 1 above. There are no proprietary frameworks or hidden dependencies.

### Limitations
- Cannot import an existing GitHub repo into Lovable (only export from Lovable to GitHub)
- Renaming, moving, or deleting the repo breaks the sync
- Only the default branch (`main`) syncs back to Lovable
- Branch switching available as experimental feature in Labs

## Key Package Dependencies (typical package.json)

### Runtime Dependencies
- `react` ^18.3.x, `react-dom` ^18.3.x
- `react-router-dom` ^6.30.x
- `@tanstack/react-query` ^5.x
- `@supabase/supabase-js` (when Supabase connected)
- `@radix-ui/react-*` (many Radix primitives for shadcn/ui)
- `lucide-react` (icons)
- `sonner` (toasts)
- `recharts` (charts)
- `react-hook-form` + `@hookform/resolvers`
- `zod` (validation)
- `class-variance-authority`, `clsx`, `tailwind-merge`
- `date-fns`
- `cmdk` (command palette)
- `vaul` (drawer)
- `embla-carousel-react`
- `next-themes` (theme switching)

### Dev Dependencies
- `vite` ^5.x
- `@vitejs/plugin-react-swc`
- `typescript` ^5.x
- `tailwindcss` ^3.x
- `autoprefixer`, `postcss`
- `eslint` + TypeScript plugin
- `lovable-tagger` (Lovable visual editor integration)

## Environment Variables
- `VITE_SUPABASE_URL` - Supabase project URL
- `VITE_SUPABASE_PUBLISHABLE_KEY` - Supabase anon/public key (safe for browser)
- Edge function secrets are stored in Supabase dashboard (e.g., `LOVABLE_API_KEY`, third-party API keys)
