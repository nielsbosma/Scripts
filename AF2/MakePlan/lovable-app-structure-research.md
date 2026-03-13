# Lovable (formerly GPT Engineer) Application Structure Research

**Date:** March 13, 2026
**Research Goal:** Understanding the architecture and structure patterns of Lovable-generated applications

## Executive Summary

Lovable (formerly GPT Engineer) is an AI-powered application generator that creates full-stack web applications. The platform primarily generates React + TypeScript applications with a consistent, opinionated architecture based on modern web development best practices.

## Key Identifying Markers

### 1. Script Tag Marker
The most reliable identifier of a Lovable-generated app is in `index.html`:
```html
<!-- IMPORTANT: DO NOT REMOVE THIS SCRIPT TAG OR THIS VERY COMMENT! -->
<script src="https://cdn.gpteng.co/gptengineer.js" type="module"></script>
```

### 2. Package Name Convention
Default package name in `package.json`:
```json
{
  "name": "vite_react_shadcn_ts"
}
```

### 3. Development Dependency
Presence of `lovable-tagger` in devDependencies:
```json
{
  "devDependencies": {
    "lovable-tagger": "^1.1.7"
  }
}
```

### 4. README Structure
READMEs consistently include:
- Project URL: `https://lovable.dev/projects/{project-id}`
- Standard sections on how to edit via Lovable, IDE, GitHub, or Codespaces
- Technology stack listing

## Core Technology Stack

### Frontend Foundation
- **Build Tool:** Vite 5.x
- **Framework:** React 18.3.x
- **Language:** TypeScript 5.5+
- **Styling:** Tailwind CSS 3.4.x
- **UI Components:** shadcn/ui (Radix UI primitives)
- **Router:** react-router-dom 6.x
- **State Management:** @tanstack/react-query 5.x
- **Forms:** react-hook-form + zod validation

### UI Component Library
Lovable apps extensively use shadcn/ui components:
- Located in `src/components/ui/`
- Typically 40-50+ pre-built components
- Includes: accordion, alert-dialog, avatar, badge, button, calendar, card, checkbox, dialog, dropdown-menu, form, input, label, popover, select, separator, slider, switch, tabs, toast, tooltip, etc.

### Backend Integration (Optional)
When backend is needed, Lovable uses:
- **Backend:** Supabase
- **Auth:** Supabase Auth with localStorage persistence
- **Database:** PostgreSQL via Supabase
- **Functions:** Deno-based Edge Functions
- **Real-time:** Supabase Realtime subscriptions

## Project Structure

### Standard Directory Layout

```
project-root/
├── .git/
├── .gitignore
├── bun.lockb              # Often uses Bun for package management
├── components.json        # shadcn/ui configuration
├── eslint.config.js
├── index.html             # Contains gptengineer.js marker
├── package.json
├── package-lock.json
├── postcss.config.js
├── public/
│   ├── favicon.ico
│   ├── placeholder.svg
│   └── robots.txt
├── README.md              # Standard Lovable README format
├── src/
│   ├── App.css
│   ├── App.tsx
│   ├── main.tsx
│   ├── index.css          # Tailwind imports + CSS variables
│   ├── vite-env.d.ts
│   ├── components/
│   │   ├── ui/            # shadcn/ui components (40-50 files)
│   │   └── [Feature].tsx  # Custom feature components
│   ├── hooks/             # Custom React hooks
│   ├── lib/
│   │   └── utils.ts       # cn() utility for classNames
│   ├── pages/
│   │   ├── Index.tsx
│   │   ├── NotFound.tsx
│   │   └── [Other].tsx
│   ├── integrations/      # Present when using Supabase
│   │   └── supabase/
│   │       ├── client.ts
│   │       └── types.ts
│   ├── contexts/          # React Context providers (optional)
│   ├── services/          # API/service layer (optional)
│   └── translations/      # i18n support (optional)
├── supabase/              # Present when using Supabase
│   ├── config.toml
│   ├── functions/
│   │   └── [function-name]/
│   │       └── index.ts
│   └── migrations/
│       └── [timestamp]_[uuid].sql
├── tailwind.config.ts
├── tsconfig.json
├── tsconfig.app.json
├── tsconfig.node.json
└── vite.config.ts
```

## Configuration Files

### 1. vite.config.ts
```typescript
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";
import { componentTagger } from "lovable-tagger";

export default defineConfig(({ mode }) => ({
  server: {
    host: "::",
    port: 8080,
  },
  plugins: [
    react(),
    mode === 'development' && componentTagger(),
  ].filter(Boolean),
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
}));
```

### 2. components.json (shadcn/ui config)
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
    "cssVariables": true,
    "prefix": ""
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

### 3. tsconfig.json
```json
{
  "files": [],
  "references": [
    { "path": "./tsconfig.app.json" },
    { "path": "./tsconfig.node.json" }
  ],
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"]
    },
    "noImplicitAny": false,
    "noUnusedParameters": false,
    "skipLibCheck": true,
    "allowJs": true,
    "noUnusedLocals": false,
    "strictNullChecks": false
  }
}
```

### 4. tailwind.config.ts
- Uses CSS variables for theming
- Includes `tailwindcss-animate` plugin
- Custom color palette based on HSL variables
- Container utility with center and padding
- Custom font families (often Work Sans, Lora, Inconsolata)

## Application Patterns

### 1. App.tsx Structure
```typescript
import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import Index from "./pages/Index";
import NotFound from "./pages/NotFound";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<Index />} />
          {/* ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE */}
          <Route path="*" element={<NotFound />} />
        </Routes>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;
```

### 2. main.tsx Entry Point
```typescript
import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";

createRoot(document.getElementById("root")!).render(<App />);
```

### 3. CSS Architecture (index.css)
```css
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  :root {
    /* CSS custom properties for colors */
    --background: 0 0% 100%;
    --foreground: 222.2 84% 4.9%;
    /* ... more variables */
  }

  .dark {
    /* Dark mode overrides */
  }
}
```

### 4. Component Organization
- **Page Components:** In `src/pages/`, one per route
- **Feature Components:** In `src/components/`, organized by feature
- **UI Components:** In `src/components/ui/`, from shadcn/ui
- **Hooks:** Custom hooks in `src/hooks/`
- **Utilities:** Helper functions in `src/lib/`

## Supabase Integration Patterns

### 1. Client Configuration
File: `src/integrations/supabase/client.ts`
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

### 2. Environment Variables (.env)
```
VITE_SUPABASE_PROJECT_ID="project-id"
VITE_SUPABASE_PUBLISHABLE_KEY="eyJhbGci..."
VITE_SUPABASE_URL="https://project-id.supabase.co"
```

### 3. Database Migrations
- Located in `supabase/migrations/`
- Naming: `[timestamp]_[uuid].sql`
- Include schema creation, RLS policies, and triggers

### 4. Edge Functions
- Located in `supabase/functions/[function-name]/index.ts`
- Use Deno runtime
- Common patterns:
  - CORS headers
  - JWT verification
  - Rate limiting
  - Supabase client initialization

### 5. Supabase Config (supabase/config.toml)
```toml
project_id = "project-id"

[functions.function-name]
verify_jwt = true
```

## Database Schema Patterns

Common entity types in Lovable apps:
```sql
-- User profiles extending auth.users
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL,
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Row Level Security
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Standard policies
CREATE POLICY "Users can view all profiles"
  ON public.profiles FOR SELECT USING (true);

CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE USING (auth.uid() = id);
```

## Advanced Features (When Present)

### 1. Native Mobile Support (Capacitor)
When apps target mobile:
- **Dependencies:** @capacitor/core, @capacitor/android, @capacitor/ios
- **Plugins:** camera, geolocation, push-notifications, share, status-bar
- **Config:** capacitor.config.ts
- **Hooks:** Custom hooks for native features in `src/hooks/`

### 2. PWA Support
- **Plugin:** vite-plugin-pwa
- **Service Worker:** Auto-generated
- **Manifest:** Configured in vite.config.ts

### 3. Internationalization
- **Directory:** `src/translations/`
- **Pattern:** JSON files per language
- **Context:** LanguageProvider/Context

### 4. Offline Support
- **Library:** idb (IndexedDB)
- **Pattern:** Offline queue in `src/lib/offlineQueue.ts`
- **Components:** OfflineIndicator component

## File Naming Conventions

### Component Files
- PascalCase: `ComponentName.tsx`
- UI components: lowercase with hyphens: `button.tsx`, `dropdown-menu.tsx`

### Hooks
- camelCase with 'use' prefix: `useAuth.ts`, `useNativeCamera.ts`

### Pages
- PascalCase: `Index.tsx`, `Dashboard.tsx`, `NotFound.tsx`

### Utilities
- camelCase: `utils.ts`, `offlineQueue.ts`

### Services
- camelCase: `nativeStatusBar.ts`, `nativeApp.ts`

## Common Dependencies

### Always Present
```json
{
  "react": "^18.3.1",
  "react-dom": "^18.3.1",
  "react-router-dom": "^6.26+",
  "@tanstack/react-query": "^5.56+",
  "lucide-react": "^0.4+",
  "tailwind-merge": "^2.5+",
  "class-variance-authority": "^0.7+",
  "clsx": "^2.1+",
  "@radix-ui/react-*": "Various versions"
}
```

### With Supabase
```json
{
  "@supabase/supabase-js": "^2.84+"
}
```

### With Forms
```json
{
  "react-hook-form": "^7.53+",
  "zod": "^3.23+",
  "@hookform/resolvers": "^3.9+"
}
```

### With Animations
```json
{
  "framer-motion": "^11.11+"
}
```

## Scripts Pattern

Standard npm scripts in `package.json`:
```json
{
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "build:dev": "vite build --mode development",
    "lint": "eslint .",
    "preview": "vite preview"
  }
}
```

## Git Integration

Lovable integrates with GitHub:
- Auto-commits changes made in Lovable IDE
- Bidirectional sync (local changes → Lovable, Lovable changes → repo)
- Standard .gitignore for Node.js/React projects

## Development Workflow

1. **In Lovable IDE:** Prompt-based development with AI
2. **Local Development:** Clone repo, `npm i`, `npm run dev`
3. **GitHub Codespaces:** Built-in support
4. **Direct GitHub Edit:** Edit files in GitHub web interface

## Deployment

Lovable provides built-in deployment:
- One-click deploy via Project > Settings > Domains
- Custom domain support
- Hosted on Lovable infrastructure
- Alternative: Self-host on Vercel, Netlify, etc.

## Anti-Patterns & Differences from Standard Apps

### More Permissive TypeScript
- `noImplicitAny: false`
- `strictNullChecks: false`
- `noUnusedLocals: false`
- Focus on rapid development over strict typing

### Component Organization
- Flat component structure (less nested than typical)
- UI components separate from feature components
- More co-location of related code

### Styling Approach
- Heavy reliance on CSS variables for theming
- Inline Tailwind classes (not CSS modules or styled-components)
- Dark mode via class-based approach

## Edge Cases & Variants

### Simple Landing Pages
- May only have Index.tsx and few components
- Minimal Supabase integration or none
- Focus on presentation

### Complex Applications
- Multiple user roles (farmer, owner, admin)
- Extensive Supabase integration
- Many pages and components (50+ components)
- Native mobile features via Capacitor
- Real-time features
- Payment integrations
- AI features (chatbots, recommendations)

## Metadata Patterns

### README.md
Always includes:
```markdown
## Project info

**URL**: https://lovable.dev/projects/{uuid}

## How can I edit this code?

[Standard sections...]

## What technologies are used for this project?

This project is built with:
- Vite
- TypeScript
- React
- shadcn-ui
- Tailwind CSS
```

### index.html
```html
<meta name="description" content="Lovable Generated Project" />
<meta name="author" content="Lovable" />
```

## Version Detection

Check for Lovable generation by looking for:
1. `gptengineer.js` script in index.html ✅ (Most reliable)
2. `lovable-tagger` in devDependencies ✅ (Very reliable)
3. Package name `vite_react_shadcn_ts` ✅ (Common but may be changed)
4. README with lovable.dev project URL ✅ (Reliable)
5. Standard shadcn/ui setup with 40+ UI components ⚠️ (Less specific)

## Key Differentiators from Other Generators

### vs Bolt.new/Bolt.diy
- Lovable uses Vite, Bolt often uses Next.js
- Lovable standardizes on shadcn/ui
- Lovable includes gptengineer.js script

### vs v0.dev
- v0 generates standalone components
- Lovable generates full applications
- Different project structure

### vs Cursor AI
- Cursor is an IDE, not a generator
- No standard project structure
- User drives architecture decisions

## Conversion Considerations

When converting Lovable apps to other platforms:

### Remove/Replace
- `gptengineer.js` script tag
- `lovable-tagger` dev dependency
- README Lovable-specific content
- Lovable project URL references

### Preserve
- Core React + Vite setup
- shadcn/ui components
- Tailwind configuration
- Component structure
- TypeScript setup

### Adapt
- Update package.json name
- Customize README
- Add own CI/CD if needed
- Update meta tags

## Summary of Key Insights

1. **Highly Opinionated Stack:** React + TypeScript + Vite + shadcn/ui + Tailwind
2. **Consistent Structure:** Predictable file organization across projects
3. **Backend = Supabase:** When backend needed, always Supabase
4. **Component-Centric:** Heavy use of pre-built shadcn/ui components
5. **Development-Focused TypeScript:** Looser type checking for speed
6. **Git-Native:** Built-in GitHub integration and sync
7. **Deployment Included:** One-click hosting available
8. **Identifiable Markers:** gptengineer.js script is the smoking gun

## Additional Resources

- **Lovable Documentation:** https://docs.lovable.dev/
- **GitHub Search:** Use queries like `"lovable-tagger"` or `"gptengineer.js"`
- **Example Repositories:** Search GitHub for "generated by lovable"
- **Lovable Downloader:** https://github.com/soranoo/lovable-downloader

---

**Research Methodology:**
- Cloned and analyzed 5+ Lovable-generated repositories
- Examined package.json, configuration files, and directory structures
- Reviewed READMEs and documentation
- Searched GitHub for patterns and common files
- Analyzed both simple landing pages and complex full-stack applications
- Examined Supabase integration patterns and migrations

**Last Updated:** March 13, 2026
