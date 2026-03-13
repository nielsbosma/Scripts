# Supabase Edge Functions in Lovable Applications

## 1. Edge Function Structure

### File Layout
Each Edge Function lives in its own directory under `supabase/functions/`, with an `index.ts` entry point:

```
supabase/
  functions/
    function-one/
      index.ts          # Entry point (required)
      deno.json         # Per-function dependency config (recommended)
    function-two/
      index.ts
      deno.json
    _shared/            # Shared code between functions (convention)
      cors.ts
      jwt/
        default.ts
    tests/
      function-one-test.ts
      function-two-test.ts
  config.toml           # Project-level config (JWT verification, import maps, etc.)
```

### Minimal Edge Function
Every Edge Function is a single `.ts` file that exports a handler via `Deno.serve()`:

```typescript
import "jsr:@supabase/functions-js/edge-runtime.d.ts"

Deno.serve(async (req) => {
  const { name } = await req.json()
  return new Response(JSON.stringify({ message: `Hello ${name}!` }), {
    headers: { "Content-Type": "application/json" },
    status: 200,
  })
})
```

Key points:
- Uses the **Web Standard Request/Response API** (not Express-style middleware)
- Each function gets its own URL: `https://<project_id>.supabase.co/functions/v1/<function-name>`
- Functions are stateless, short-lived, idempotent
- No `export default` - just call `Deno.serve()`

---

## 2. Deno Runtime

Edge Functions run on **Supabase Edge Runtime** (Deno-compatible). Implications:

### Import Patterns
```typescript
// NPM packages (recommended pattern)
import { createClient } from 'npm:@supabase/supabase-js@2'
import Stripe from 'npm:stripe@14'

// Node.js built-ins
import process from 'node:process'

// JSR modules (Deno's registry)
import path from 'jsr:@std/path@1.0.8'

// URL imports (older pattern, still works)
import Stripe from 'https://esm.sh/stripe@14?target=denonext'

// Relative imports for shared code
import { corsHeaders } from '../_shared/cors.ts'
```

### TypeScript
- TypeScript first - no build step needed, types work natively
- For packages without types: `// @deno-types="npm:@types/express@^4.17"`
- For Node built-in types: `/// <reference types="npm:@types/node" />`

### Key Deno Differences from Node.js
- No `require()` - ESM imports only
- No `package.json` - use `deno.json` or `import_map.json`
- No `node_modules/` directory
- Environment variables via `Deno.env.get('NAME')` (not `process.env.NAME`)
- Web standard APIs (fetch, Request, Response, crypto) are built-in
- File extensions required in relative imports (`.ts`)

---

## 3. Common Edge Function Patterns in Lovable

Lovable apps typically use Edge Functions for these scenarios:

### a) Stripe Payment Processing
- Checkout session creation
- Webhook handling for payment events
- Subscription management
- The most common integration - Lovable auto-scaffolds these

```typescript
// Stripe webhook handler pattern
import Stripe from 'https://esm.sh/stripe@14?target=denonext'

const stripe = new Stripe(Deno.env.get('STRIPE_API_KEY')!, {
  apiVersion: '2024-11-20',
})
const cryptoProvider = Stripe.createSubtleCryptoProvider()

Deno.serve(async (request) => {
  const signature = request.headers.get('Stripe-Signature')
  const body = await request.text()

  let receivedEvent
  try {
    receivedEvent = await stripe.webhooks.constructEventAsync(
      body, signature!,
      Deno.env.get('STRIPE_WEBHOOK_SIGNING_SECRET')!,
      undefined, cryptoProvider
    )
  } catch (err) {
    return new Response(err.message, { status: 400 })
  }

  // Handle event types: payment_intent.succeeded, customer.subscription.created, etc.
  return new Response(JSON.stringify({ ok: true }), { status: 200 })
})
```

### b) AI/LLM API Integration
- OpenAI, Anthropic, Hugging Face calls
- API keys stored as secrets, called from Edge Function to keep keys server-side

### c) Email Sending
- Via Resend, SendGrid, or other email APIs
- Welcome emails, notifications, transactional emails

### d) External API Proxying
- Any third-party API that requires secret keys
- Keeps API keys server-side, out of the browser

### e) Custom Business Logic
- Data processing, validation
- Complex operations that shouldn't run client-side

---

## 4. Edge Function Configuration

### Environment Variables / Secrets

**Default (automatic) secrets available in every function:**
- `SUPABASE_URL` - API gateway URL
- `SUPABASE_ANON_KEY` - public anon key (safe for client, respects RLS)
- `SUPABASE_SERVICE_ROLE_KEY` - admin key (bypasses RLS - server only!)
- `SUPABASE_DB_URL` - direct Postgres connection URL

**Hosted-only env vars:**
- `SB_REGION` - region where function was invoked
- `SB_EXECUTION_ID` - UUID of the function instance
- `DENO_DEPLOYMENT_ID` - version identifier

**Accessing secrets in code:**
```typescript
const stripeKey = Deno.env.get('STRIPE_SECRET_KEY')
```

**Local development secrets:**
- Place in `supabase/functions/.env` (auto-loaded on `supabase start`)
- Or use `supabase functions serve --env-file .env.local`
- Never commit `.env` files to git

**Production secrets:**
- Dashboard: Edge Function Secrets Management page
- CLI: `supabase secrets set --env-file .env`
- CLI: `supabase secrets set STRIPE_SECRET_KEY=sk_live_...`
- Secrets are available immediately, no re-deploy needed

### CORS Configuration

Required for browser invocation. Recommended approach (SDK v2.95.0+):

```typescript
import { corsHeaders } from '@supabase/supabase-js/cors'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  // ... handle request
  return new Response(JSON.stringify(data), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
})
```

Legacy approach (shared file):
```typescript
// supabase/functions/_shared/cors.ts
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
```

### JWT Verification / Auth

By default, Edge Functions require a valid JWT in the Authorization header. Configure in `config.toml`:

```toml
[functions.hello-world]
verify_jwt = false    # Disable for webhooks (e.g., Stripe)
```

Or deploy with flag: `supabase functions deploy hello-world --no-verify-jwt`

For custom JWT verification, use the `_shared/jwt/` pattern with `jose` library.

---

## 5. Edge Function Deployment

### From Supabase CLI (standard approach)
```bash
supabase login
supabase link --project-ref your-project-id
supabase functions deploy              # Deploy all functions
supabase functions deploy hello-world  # Deploy single function
supabase functions deploy hello-world --no-verify-jwt  # Public endpoint
```

### From Lovable
- Lovable generates Edge Function code and deploys it directly to the connected Supabase project
- When you describe backend behavior in chat, Lovable writes the function and deploys it
- Lovable also reads Edge Function logs from Supabase dashboard to help debug errors
- The connection is through Lovable's native Supabase integration (OAuth-based)

### CI/CD (GitHub Actions)
```yaml
name: Deploy Function
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
      PROJECT_ID: your-project-id
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v1
        with:
          version: latest
      - run: supabase functions deploy --project-ref $PROJECT_ID
```

### From Supabase Dashboard
- Edge Functions can also be created, edited, and deployed directly from the Dashboard editor
- Built-in syntax highlighting and type-checking for Deno

---

## 6. Edge Function to .NET/C# Backend Conversion

When converting Supabase Edge Functions to a traditional .NET/C# backend (like Ivy), the following mappings apply:

### Request/Response Pattern
| Edge Function (Deno) | .NET Equivalent |
|---|---|
| `Deno.serve(async (req) => { ... })` | ASP.NET Controller action or Minimal API endpoint |
| `req.json()` | `[FromBody] MyDto dto` parameter binding |
| `new Response(JSON.stringify(data), { status: 200 })` | `return Ok(data)` or `Results.Ok(data)` |
| `req.headers.get('Authorization')` | `Request.Headers["Authorization"]` |
| `req.method === 'OPTIONS'` | CORS middleware handles this automatically |

### Environment/Secrets
| Edge Function | .NET Equivalent |
|---|---|
| `Deno.env.get('STRIPE_SECRET_KEY')` | `IConfiguration["Stripe:SecretKey"]` or `Environment.GetEnvironmentVariable()` |
| Supabase Secrets dashboard | Azure Key Vault, User Secrets, or `appsettings.json` |
| `.env` file | `appsettings.Development.json` or .NET User Secrets |

### CORS
| Edge Function | .NET Equivalent |
|---|---|
| Manual `corsHeaders` on every response | `app.UseCors()` middleware with policy |
| OPTIONS preflight handler | Handled automatically by CORS middleware |

### Authentication
| Edge Function | .NET Equivalent |
|---|---|
| Manual JWT parsing in each function | `[Authorize]` attribute + JWT Bearer middleware |
| `supabase.auth.getClaims(token)` | `User.Claims` from HttpContext |
| `verify_jwt = false` in config.toml | `[AllowAnonymous]` attribute |

### Stripe Webhooks
| Edge Function | .NET Equivalent |
|---|---|
| `stripe.webhooks.constructEventAsync()` | `EventUtility.ConstructEventAsync()` from Stripe.NET |
| `Deno.env.get('STRIPE_WEBHOOK_SIGNING_SECRET')` | `IConfiguration["Stripe:WebhookSecret"]` |

### Dependency Management
| Edge Function | .NET Equivalent |
|---|---|
| `npm:` / `jsr:` / URL imports | NuGet packages |
| `deno.json` imports map | `.csproj` PackageReference |
| `import_map.json` (legacy) | N/A |

### General Conversion Strategy
1. **Each Edge Function becomes a Controller or Minimal API endpoint group** - one function = one route handler
2. **Shared code (`_shared/`)** becomes shared services/middleware in DI container
3. **Secrets** move to .NET configuration system (appsettings, env vars, Key Vault)
4. **CORS** is handled by ASP.NET CORS middleware globally
5. **Auth** is handled by ASP.NET JWT Bearer authentication middleware
6. **The Supabase client** is replaced by direct DB access (EF Core) or Supabase .NET client
7. **Stripe integration** uses Stripe.NET NuGet package instead of the JS SDK

---

## 7. Shared Types

### The Problem
Lovable apps (React/TypeScript frontend) and Edge Functions (Deno/TypeScript) both need access to the same types, especially database types generated by Supabase.

### Common Approaches

**1. Generated Database Types (supabase gen types)**
```bash
supabase gen types typescript --local > src/types/database.types.ts
```
This generates TypeScript types from your Postgres schema. The challenge is that Edge Functions (Deno) and the frontend (Vite/React) have different module resolution.

**2. Shared `_shared/` directory**
Place shared types/utilities in `supabase/functions/_shared/`:
```
supabase/functions/_shared/
  types.ts        # Shared type definitions
  cors.ts         # Shared CORS headers
  jwt/default.ts  # Shared auth middleware
```
Import in functions: `import { MyType } from '../_shared/types.ts'`

**3. Manual duplication**
In practice, many Lovable apps duplicate type definitions between frontend (`src/types/`) and edge functions. This is a known pain point.

**4. The GitHub Discussion (#28837)**
The Supabase community has discussed this issue. Current recommendation is to generate types and reference them from both locations, potentially using path aliases in `deno.json`.

### Lovable-Specific Behavior
- Lovable generates SQL schema and frontend types as part of its chat-driven workflow
- The AI keeps types in sync when modifying both frontend and backend
- But there's no automatic type-sharing mechanism - it's the AI maintaining consistency

---

## 8. Edge Function Triggers

Edge Functions can be triggered in several ways:

### a) HTTP Invocation (most common)
From frontend using Supabase client:
```typescript
const { data, error } = await supabase.functions.invoke('function-name', {
  body: { key: 'value' },
})
```
Or via direct HTTP POST:
```
POST https://<project_id>.supabase.co/functions/v1/<function-name>
Authorization: Bearer <anon_key_or_user_jwt>
Content-Type: application/json
```

### b) Webhook Receivers
- External services (Stripe, GitHub, etc.) send POST requests to the function URL
- Typically deployed with `--no-verify-jwt` since external services can't provide Supabase JWTs
- Verification done via service-specific signatures (e.g., Stripe signature verification)

### c) Cron / Scheduled (via pg_cron + pg_net)
Uses Postgres extensions to invoke functions on a schedule:
```sql
-- Store secrets in Vault
select vault.create_secret('https://project-ref.supabase.co', 'project_url');
select vault.create_secret('YOUR_SUPABASE_ANON_KEY', 'anon_key');

-- Schedule function invocation every minute
select cron.schedule(
  'invoke-function-every-minute',
  '* * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/function-name',
    headers := jsonb_build_object(
      'Content-type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'anon_key')
    ),
    body := concat('{"time": "', now(), '"}')::jsonb
  ) as request_id;
  $$
);
```

### d) Database Webhooks (via pg_net)
Postgres triggers can call Edge Functions when data changes:
- Use `pg_net` to make HTTP requests from within database triggers
- Enables "when row inserted in table X, call function Y" patterns

### e) Auth Hooks
Supabase Auth can trigger Edge Functions for:
- Send Email Hook (custom email sending)
- Send SMS Hook (custom SMS sending)

---

## 9. Edge Function Dependencies

### Recommended: `deno.json` (per-function)
```json
{
  "imports": {
    "@supabase/supabase-js": "npm:@supabase/supabase-js@2",
    "stripe": "npm:stripe@14",
    "openai": "npm:openai@4"
  }
}
```
Place in each function's directory for isolation.

### Legacy: `import_map.json`
```json
{
  "imports": {
    "stripe": "https://esm.sh/stripe@14?target=denonext"
  }
}
```
If both `deno.json` and `import_map.json` exist, `deno.json` takes precedence.

### Import Sources (supported)
1. **npm packages**: `import X from 'npm:package@version'` (recommended)
2. **JSR modules**: `import X from 'jsr:@scope/package@version'`
3. **URL imports**: `import X from 'https://esm.sh/package'`
4. **deno.land/x**: `import X from 'https://deno.land/x/package/mod.ts'`
5. **Node built-ins**: `import X from 'node:module'`

### Private NPM Packages
Create `.npmrc` in the function directory:
```
@myorg:registry=https://npm.registryhost.com
//npm.registryhost.com/:_authToken=VALID_AUTH_TOKEN
```

### Dependency Analysis
```bash
deno info /path/to/function/index.ts
deno info --import-map=./deno.json /path/to/function/index.ts
```

### config.toml for Import Map Location
```toml
[functions.my-function]
import_map = "./supabase/functions/my-function/import_map.json"
```

---

## Sources
- https://supabase.com/docs/guides/functions
- https://supabase.com/docs/guides/functions/deploy
- https://supabase.com/docs/guides/functions/secrets
- https://supabase.com/docs/guides/functions/cors
- https://supabase.com/docs/guides/functions/dependencies
- https://supabase.com/docs/guides/functions/schedule-functions
- https://supabase.com/docs/guides/functions/auth
- https://supabase.com/docs/guides/functions/examples/stripe-webhooks
- https://docs.lovable.dev/integrations/supabase
- https://docs.lovable.dev/integrations/stripe
- https://github.com/orgs/supabase/discussions/28837 (shared types discussion)
