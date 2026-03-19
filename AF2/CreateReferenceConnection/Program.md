# CreateReferenceConnection

> **⚠️ WRITE SCOPE: You may only create/edit files under `D:\Repos\_Ivy\Ivy\connections\` (connection implementations and research). You may READ any source files for reference.**

Research, build, and test a new reference connection for the Ivy ecosystem following the established pattern.

## Context

Reference connections are third-party API integrations that Ivy can use. Each connection gets its own research document in `D:\Repos\_Ivy\Ivy\connections\.research\` describing the service, available NuGet packages, OpenAPI specs, authentication, and how to obtain API keys.

The research phase is critical to ensure we select the best implementation approach before creating the actual connection implementation.

## Execution Steps

### 1. Parse Args

Args should contain the name of the service to research (e.g., "Stripe", "Twilio", "SendGrid").

### 2. Research Phase

Create a comprehensive markdown file at `D:\Repos\_Ivy\Ivy\connections\.research\<ServiceName>.md` that includes:

#### A. Service Overview
- Brief description of what the service does
- Primary use cases
- Official website and documentation links

#### B. NuGet Package Analysis

Search for available .NET packages for this service. For each candidate package, evaluate:

**GOOD indicators:**
- Many downloads (10,000+)
- Recently updated (within last 6 months)
- Copyleft license (MIT, Apache, etc.)
- Good documentation
- Official package created by the service provider
- Support for IChatClient (if applicable for AI services)
- Multi-framework support (.NET 8.0, .NET Standard 2.0, etc.)
- Active GitHub repository with stars and contributors

**BAD indicators:**
- Few downloads (<1,000)
- Not updated in a long time (>1 year)
- Restrictive license (GPL, etc.)
- No documentation
- Abandoned or unmaintained
- Third-party with no official alternative

For each package include:
- Package name and NuGet link
- Version number
- Download count
- Last update date
- License type
- Target frameworks
- Dependencies
- Project URL
- Documentation URL
- Official vs Third-Party status
- GitHub stars/contributors (if available)
- Notes about special features or limitations

**Recommendation:** Clearly state which package is recommended and why. If there's no good NuGet package, recommend using the OpenAPI spec with a code generator (NSwag, Kiota, or AutoRest).

#### C. OpenAPI / Swagger Specification

Search for an official OpenAPI/Swagger specification:
- OpenAPI JSON URL
- OpenAPI YAML URL
- Interactive API documentation URL
- GitHub repository for the spec (if available)
- Note whether it's OpenAPI 2.0 or 3.x

If an OpenAPI spec exists, mention that it can be used to generate a client.

#### D. Required Secrets / API Keys

Document what authentication credentials are needed:
- Type of authentication (API key, OAuth, Bearer token, etc.)
- Secret names (e.g., `API_KEY`, `CLIENT_ID`, `CLIENT_SECRET`)
- Format of the secrets
- Whether they expire
- Scope/permissions available
- Security features (rotation, expiration, compromise detection, etc.)

**IMPORTANT:** We're looking for **server-side API keys** that can be used on a backend server, NOT OAuth user authentication flows.

#### E. How to Obtain Secrets / API Keys

Provide **step-by-step instructions** for developers to get these secrets:

1. Account creation process (signup URL, requirements)
2. Navigation to API/integration settings (exact URLs)
3. Creating/generating API keys
4. Configuring permissions/scopes (if applicable)
5. Copying and storing the secrets securely
6. How to use the secrets (environment variables, configuration)
7. How to verify the secrets work
8. Token rotation/refresh process (if applicable)

Be specific with URLs, button names, and menu paths so someone can follow along easily.

### 3. Validation

Before finalizing, verify:
- [ ] All URLs are valid and accessible
- [ ] NuGet package information is current
- [ ] API documentation links work
- [ ] The recommended package is clearly stated with justification
- [ ] Step-by-step secret acquisition is complete and actionable
- [ ] The document follows the format of existing research files (see `Apify.md`, `Cohere.md` as examples)

### 4. Existing Connection Check

Before finalizing, check if a connection already exists:
- Check if `D:\Repos\_Ivy\Ivy\connections\<ServiceName>\` exists
- If it exists, still create/update the research file but note in the summary that implementation already exists

### 5. Build Phase

After research is complete, build the connection implementation.

#### Pre-build Setup

[ ] Check existing connections in the parent folder (`D:\Repos\_Ivy\Ivy\connections\`) for patterns to follow. Learn from existing connections for the new one we are creating.

[ ] Confirm the service name and which API/sub-API to target. Sometimes a service has multiple APIs (e.g., Stripe has payments, billing, customers). If unclear, **ask the user** to clarify which API to target. This should be reflected in the connection name and description.

[ ] **Ask the user which build approach to use.** Present the three options based on the research:

1. **NuGet package** (preferred) — if a good NuGet exists → proceed to **Path A**
2. **OpenAPI/Swagger spec** — if no good NuGet but spec exists → proceed to **Path B**
3. **Custom HTTP client** — last resort → proceed to **Path C**

**Notes on approach selection:**
- For LLM-related connections, prefer packages with `Microsoft.Extensions.AI` / `IChatClient` support. It's fine to also register the provider-specific client, but always want `IChatClient` as well if possible for a unified chat interface.

[ ] Find an SVG logo for the connection. Try these sites:
  - https://www.svgrepo.com/
  - https://cdn.brandfetch.io/domain/<domain>
- Logos should be squared, ~200x200 pixels, transparent background, centered
- Save as `logo.svg` in the connection directory (e.g., `connections/[ConnectionName]/logo.svg`)

[ ] Create the `Ivy.Connections.[ConnectionName]` subfolder inside the working directory for the dotnet project.

**Expected directory structure:**
```
connections/[ConnectionName]/
├── connection.yaml
├── logo.svg
└── Ivy.Connections.[ConnectionName]/
    ├── Ivy.Connections.[ConnectionName].csproj
    ├── Program.cs
    ├── Connections/
    │   └── [ConnectionName]Connection.cs
    ├── Apps/
    │   └── [ConnectionName]App.cs
    └── Tests/
        └── [ConnectionName]ConnectionTests.cs
```

#### Common Setup (all paths)

[ ] Create a new dotnet 10.0 console project in the `Ivy.Connections.[ConnectionName]` subfolder using the dotnet CLI.

[ ] Configure the csproj `<PropertyGroup>` with standard Ivy connection settings:

```xml
<NoWarn>CS8618;CS8603;CS8602;CS8604;CS8625;CS9113</NoWarn>
<GenerateProgramFile>false</GenerateProgramFile>
```

- `NoWarn` suppresses common nullable reference type warnings that occur frequently with SDK types and Ivy state hooks.
- `GenerateProgramFile` prevents `Microsoft.NET.Test.Sdk` from generating an `AutoGeneratedProgram.Main` that conflicts with the top-level `Program.cs` entry point (CS7022).

[ ] Add the Ivy framework dependency. In the monorepo, add a relative `<ProjectReference>` to `Ivy.csproj`:

```xml
<ProjectReference Include="..\..\..\..\Ivy-Framework\src\Ivy\Ivy.csproj" />
```

For published connections outside the monorepo, use the `Ivy` NuGet package instead.

[ ] Add the project to `connections.slnx` (in the parent of the working directory). Use the dotnet CLI — don't put it in a folder!

---

#### Path A: NuGet Package

[ ] Add the selected NuGet package to the project via dotnet CLI.

[ ] Create `Connections/[ConnectionName]Connection.cs` implementing `IConnection` and `IHaveSecrets` (see interface definitions below).

[ ] Initialize dotnet user secrets for the project.

[ ] **Ask the user** what secrets/API keys are needed to connect to the API and ask for the values. Store in user secrets using naming like `[ConnectionName]:[SecretName]` (e.g., `Stripe:ApiKey`).

[ ] Using the az CLI, add all secrets to Azure Key Vault `keyvault-ivy-dev`. **Important:** `:` must be replaced with `--` in Key Vault secret names:

```bash
az keyvault secret set --vault-name keyvault-ivy-dev --name "[ConnectionName]--[SecretName]" --value "<secret-value>"
```

[ ] Copy `.templates/env.config.yaml` and `.templates/SetupLocalDevelopment.ps1` from the parent of the working directory into the `Ivy.Connections.[ConnectionName]` subfolder.

[ ] Modify the copied `env.config.yaml` to list all secret keys using the `:` form:

```yaml
keyVault: keyvault-ivy-dev
secrets:
  - [ConnectionName]:ApiKey
```

[ ] Add xUnit test packages: `xunit`, `xunit.runner.visualstudio`, and `Microsoft.NET.Test.Sdk`.

[ ] Create `Tests/[ConnectionName]ConnectionTests.cs` with xUnit tests (see testing guidelines below).

[ ] Run `dotnet test` until all unit tests pass. Integration tests may fail without credentials — that is expected.

[ ] Create `Program.cs` as Ivy app launcher (see Program.cs template below).

[ ] Create `Apps/` folder with 1-3 demo apps (see app guidelines below).

[ ] Run `dotnet build` to verify everything compiles.

---

#### Path B: OpenAPI/Swagger Spec

[ ] Find the official OpenAPI/Swagger spec URL. Common locations:
  - `https://api.example.com/openapi.json`
  - `https://api.example.com/swagger.json`
  - API documentation site
  - GitHub repositories

Validate it returns a valid OpenAPI 2.0/3.0/3.1 spec. Ask the user to confirm.

> **Note — YAML specs may fail to parse with Refitter.**
> Refitter's YAML parser can choke on certain YAML constructs. If Refitter fails with a parse error on a YAML spec, convert to JSON first:
> ```bash
> python -c "import yaml, json, sys; json.dump(yaml.safe_load(open(sys.argv[1])), open(sys.argv[2], 'w'), indent=2)" spec.yaml spec.json
> ```

[ ] Determine the authentication scheme (Bearer token, API key header, etc.). Note the auth type and header name.

[ ] **Ask the user** for the API endpoint base URL and their API key/token. Store as user secrets:

```bash
dotnet user-secrets set "[ConnectionName]:EndpointUrl" "<endpoint-url>"
dotnet user-secrets set "[ConnectionName]:BearerToken" "<token>"   # for bearer auth
# OR
dotnet user-secrets set "[ConnectionName]:ApiKey" "<api-key>"       # for API key auth
```

[ ] Add all secrets to Azure Key Vault `keyvault-ivy-dev` (`:` → `--` in names):

```bash
az keyvault secret set --vault-name keyvault-ivy-dev --name "[ConnectionName]--EndpointUrl" --value "<endpoint-url>"
az keyvault secret set --vault-name keyvault-ivy-dev --name "[ConnectionName]--BearerToken" --value "<token>"
```

[ ] Install Refitter globally and add Refit NuGet:

```bash
dotnet tool install --global refitter
dotnet add package Refit
```

[ ] Create `Connections/[ConnectionName]/[ConnectionName].refitter` config:

```json
{
    "openApiPath": "<OpenAPI spec URL>",
    "namespace": "Ivy.Connections.[ConnectionName].Connections.[ConnectionName]",
    "outputFilename": "<absolute path to Connections/[ConnectionName]/[ConnectionName]Client.cs>",
    "naming": {
        "useOpenApiTitle": false,
        "interfaceName": "[ConnectionName]Client"
    },
    "immutableRecords": false,
    "operationNameGenerator": "SingleClientFromPathSegments",
    "optionalParameters": true,
    "addAutoGeneratedHeader": false,
    "generateXmlDocCodeComments": false,
    "generateStatusCodeComments": false,
    "codeGeneratorSettings": {
        "generateOptionalPropertiesAsNullable": true,
        "generateNullableReferenceTypes": true
    }
}
```

Key settings:
- `operationNameGenerator: "SingleClientFromPathSegments"` — cleaner method names from URL paths
- `optionalParameters: true` — optional query params become C# optional parameters
- `interfaceName` — omits `I` prefix; Refitter adds it automatically, producing `I[ConnectionName]Client`

[ ] Generate the client:

```bash
refitter --settings-file "Connections/[ConnectionName]/[ConnectionName].refitter" --skip-validation --no-banner
```

> **Warning — Generated model types can shadow system types.**
> Some OpenAPI specs define classes like `CancellationToken`, `Task`, or `WaitHandle` that shadow `System.Threading` types. If you see build errors in `SendAsync` or similar:
> 1. Use fully qualified system type names (e.g. `System.Threading.CancellationToken`)
> 2. Or place the factory/connection class in a parent namespace that doesn't import generated models

[ ] Create `Connections/[ConnectionName]/Refresh.ps1` for client regeneration:

```powershell
# Regenerates the [ConnectionName] API client from the OpenAPI spec.
# Prerequisites: dotnet tool install --global refitter

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsFile = Join-Path $scriptDir "[ConnectionName].refitter"

# If spec is YAML, uncomment to convert to JSON first:
# $yamlSpec = Join-Path $scriptDir "spec.yaml"
# $jsonSpec = Join-Path $scriptDir "spec.json"
# python -c "import yaml, json, sys; json.dump(yaml.safe_load(open(sys.argv[1])), open(sys.argv[2], 'w'), indent=2)" $yamlSpec $jsonSpec

Write-Host "Regenerating [ConnectionName] client from OpenAPI spec..." -ForegroundColor Cyan
refitter --settings-file $settingsFile --skip-validation --no-banner

if ($LASTEXITCODE -eq 0) {
    Write-Host "Client regenerated successfully." -ForegroundColor Green
} else {
    Write-Host "Refitter failed with exit code $LASTEXITCODE." -ForegroundColor Red
    exit $LASTEXITCODE
}
```

[ ] Create `Connections/[ConnectionName]/[ConnectionName]ClientFactory.cs`:

```csharp
using Microsoft.Extensions.Configuration;
using Refit;

namespace Ivy.Connections.[ConnectionName].Connections.[ConnectionName];

public static class [ConnectionName]ClientFactory
{
    private class [ConnectionName]AuthHandler : DelegatingHandler
    {
        private readonly string _token;
        private readonly string _headerName;
        private readonly bool _isBearer;

        public [ConnectionName]AuthHandler(string token, string headerName, bool isBearer)
        {
            _token = token;
            _headerName = headerName;
            _isBearer = isBearer;
            InnerHandler = new HttpClientHandler();
        }

        // Use fully qualified System.Threading.CancellationToken in case generated
        // models shadow the system type.
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, System.Threading.CancellationToken cancellationToken)
        {
            if (_isBearer)
                request.Headers.Add(_headerName, $"Bearer {_token}");
            else
                request.Headers.Add(_headerName, _token);
            return base.SendAsync(request, cancellationToken);
        }
    }

    public static I[ConnectionName]Client CreateClient(IConfiguration config)
    {
        var endpointUrl = config.GetValue<string>("[ConnectionName]:EndpointUrl")
            ?? throw new Exception("[ConnectionName]:EndpointUrl is required");
        var token = config.GetValue<string>("[ConnectionName]:BearerToken")  // or [ConnectionName]:ApiKey
            ?? throw new Exception("[ConnectionName]:BearerToken is required");

        return RestService.For<I[ConnectionName]Client>(endpointUrl, new RefitSettings
        {
            HttpMessageHandlerFactory = () => new [ConnectionName]AuthHandler(token, "Authorization", true)
            // For API key auth: new [ConnectionName]AuthHandler(token, "X-Api-Key", false)
        });
    }
}
```

[ ] Create `Connections/[ConnectionName]/[ConnectionName]Connection.cs` implementing `IConnection` and `IHaveSecrets`:

```csharp
using Ivy;
using System.Reflection;

namespace Ivy.Connections.[ConnectionName].Connections.[ConnectionName];

public class [ConnectionName]Connection : IConnection, IHaveSecrets
{
    public string GetContext(string connectionPath)
    {
        var connectionFile = nameof([ConnectionName]Connection) + ".cs";
        var clientFactoryFile = nameof([ConnectionName]ClientFactory) + ".cs";
        var files = Directory.GetFiles(connectionPath, "*.*", SearchOption.TopDirectoryOnly)
            .Where(f => !f.EndsWith(connectionFile) && !f.EndsWith(clientFactoryFile))
            .Select(File.ReadAllText)
            .ToArray();
        return string.Join(Environment.NewLine, files);
    }

    public string GetName() => nameof([ConnectionName]);
    public string GetNamespace() => typeof([ConnectionName]Connection).Namespace;
    public string GetConnectionType() => "OpenApi.Rest";

    public ConnectionEntity[] GetEntities()
    {
        var clientType = typeof(I[ConnectionName]Client);
        var methods = clientType.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly);
        return methods.Select(m => new ConnectionEntity(m.Name, m.Name)).ToArray();
    }

    public void RegisterServices(Server server)
    {
        server.Services.AddTransient<I[ConnectionName]Client>(sp =>
        {
            var config = sp.GetRequiredService<IConfiguration>();
            return [ConnectionName]ClientFactory.CreateClient(config);
        });
    }

    public Secret[] GetSecrets() =>
    [
        new Secret("[ConnectionName]:EndpointUrl"),
        new Secret("[ConnectionName]:BearerToken")  // or [ConnectionName]:ApiKey
    ];

    public async Task<(bool ok, string? message)> TestConnection(IConfiguration config)
    {
        try
        {
            var client = [ConnectionName]ClientFactory.CreateClient(config);
            // Call a lightweight read-only endpoint to verify connectivity
            return (true, null);
        }
        catch (Exception ex)
        {
            return (false, $"Connection test failed: {ex.Message}");
        }
    }
}
```

[ ] Copy `.templates/env.config.yaml` and `.templates/SetupLocalDevelopment.ps1` into the `Ivy.Connections.[ConnectionName]` subfolder. Modify `env.config.yaml` to list all secret keys.

[ ] Add xUnit test packages, create tests, Program.cs, and apps (same as Path A — see templates below).

[ ] Run `dotnet test` and `dotnet build` to verify.

---

#### Path C: Custom HTTP Client

[ ] Read the official API documentation. Identify:
  - Base URL and versioning scheme
  - Authentication method
  - The 5-10 most important read-only endpoints
  - Request/response formats
  - Rate limiting and pagination patterns
  - Error response format

[ ] **Ask the user** to confirm which endpoints are most important.

[ ] **Ask the user** for the API base URL and API key/token. Store as user secrets:

```bash
dotnet user-secrets init
dotnet user-secrets set "[ConnectionName]:BaseUrl" "<base-url>"
dotnet user-secrets set "[ConnectionName]:ApiKey" "<api-key>"
```

[ ] Add all secrets to Azure Key Vault `keyvault-ivy-dev` (`:` → `--` in names):

```bash
az keyvault secret set --vault-name keyvault-ivy-dev --name "[ConnectionName]--BaseUrl" --value "<base-url>"
az keyvault secret set --vault-name keyvault-ivy-dev --name "[ConnectionName]--ApiKey" --value "<api-key>"
```

[ ] Create `Connections/[ConnectionName]Client.cs` with a typed HTTP client:

```csharp
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Ivy.Connections.[ConnectionName].Connections.[ConnectionName];

public interface I[ConnectionName]Client
{
    // One method per endpoint, grouped logically
    Task<ListResponse<Item>> GetItemsAsync(int? page = null, int? pageSize = null, CancellationToken ct = default);
    Task<Item> GetItemByIdAsync(string id, CancellationToken ct = default);
}

public class [ConnectionName]Client : I[ConnectionName]Client
{
    private readonly HttpClient _http;
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public [ConnectionName]Client(HttpClient http)
    {
        _http = http;
    }

    public async Task<ListResponse<Item>> GetItemsAsync(int? page = null, int? pageSize = null, CancellationToken ct = default)
    {
        var query = new List<string>();
        if (page.HasValue) query.Add($"page={page}");
        if (pageSize.HasValue) query.Add($"page_size={pageSize}");
        var qs = query.Count > 0 ? "?" + string.Join("&", query) : "";

        var response = await _http.GetAsync($"/items{qs}", ct);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<ListResponse<Item>>(JsonOptions, ct))!;
    }
}

// Response model patterns — adapt to the actual API
public record ListResponse<T>(
    [property: JsonPropertyName("data")] T[] Data,
    [property: JsonPropertyName("total")] int Total,
    [property: JsonPropertyName("has_more")] bool HasMore
);

public record Item(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("created_at")] DateTimeOffset CreatedAt
);
```

Guidelines for the custom client:
- Define `I[ConnectionName]Client` interface for DI and mocking
- Use `System.Net.Http.Json` (no external dependencies)
- Use `System.Text.Json` with `CamelCase` naming and `WhenWritingNull`
- All methods async with `CancellationToken` support
- Optional parameters for query string params
- Use `record` types for response models
- Only implement read-only endpoints first
- Group related models in `Models/` if the API surface is large

[ ] Create `Connections/[ConnectionName]Connection.cs` implementing `IConnection` and `IHaveSecrets`:

```csharp
public class [ConnectionName]Connection : IConnection, IHaveSecrets
{
    public string GetName() => "[ConnectionName]";
    public string GetNamespace() => typeof([ConnectionName]Connection).Namespace;
    public string GetConnectionType() => "Custom";

    public void RegisterServices(Server server)
    {
        server.Services.AddTransient<I[ConnectionName]Client>(sp =>
        {
            var config = sp.GetRequiredService<IConfiguration>();
            var baseUrl = config["[ConnectionName]:BaseUrl"]
                ?? throw new Exception("[ConnectionName]:BaseUrl is required");
            var apiKey = config["[ConnectionName]:ApiKey"]
                ?? throw new Exception("[ConnectionName]:ApiKey is required");

            var http = new HttpClient { BaseAddress = new Uri(baseUrl) };
            http.DefaultRequestHeaders.Add("Authorization", $"Bearer {apiKey}");
            // OR: http.DefaultRequestHeaders.Add("X-Api-Key", apiKey);

            return new [ConnectionName]Client(http);
        });
    }

    public Secret[] GetSecrets() =>
    [
        new Secret("[ConnectionName]:BaseUrl"),
        new Secret("[ConnectionName]:ApiKey")
    ];

    public string GetContext(string connectionPath)
    {
        return """
            ## [ConnectionName] API Client

            Get the client:
            var client = UseService<I[ConnectionName]Client>();

            // List items
            var items = await client.GetItemsAsync(page: 1, pageSize: 10);

            // Get single item
            var item = await client.GetItemByIdAsync("item-id");
            """;
    }

    public ConnectionEntity[] GetEntities() => [ /* fill based on API resources */ ];

    public async Task<(bool ok, string? message)> TestConnection(IConfiguration config)
    {
        try
        {
            // Call a lightweight endpoint to verify connectivity
            return (true, null);
        }
        catch (Exception ex)
        {
            return (false, $"Connection test failed: {ex.Message}");
        }
    }
}
```

[ ] Copy `.templates/env.config.yaml` and `.templates/SetupLocalDevelopment.ps1` into the `Ivy.Connections.[ConnectionName]` subfolder. Modify `env.config.yaml`:

```yaml
keyVault: keyvault-ivy-dev
secrets:
  - [ConnectionName]:BaseUrl
  - [ConnectionName]:ApiKey
```

[ ] Add xUnit test packages, create tests, Program.cs, and apps (same patterns — see templates below).

[ ] Run `dotnet test` and `dotnet build` to verify.

---

#### Interface Definitions

The connection class must implement `IConnection` (and `IHaveSecrets`). Both interfaces live in **`namespace Ivy;`** (defined in `Ivy-Framework/src/Ivy/Abstractions/`).

```csharp
namespace Ivy;

public interface IConnection
{
    /* Return a string with instructions on how to use this connection. This is presented to LLMs when they want to use the connection. It should include:
       - How to get the service: var client = UseService<IServiceInterface>();
       - The most common usage examples with code snippets
       - Information about response types and error handling
       Do NOT read files from disk. Return a raw string literal with the documentation. */
    public string GetContext(string connectionPath);
    public string GetNamespace();
    public string GetName();
    /* For nuget based connections this should return "Nuget:[PackageId]" */
    public string GetConnectionType();
    /* For some connections there might be different entities such as Customer, Suppliers etc. Present them here. */
    public ConnectionEntity[] GetEntities();
    /* What services should be registered in the Ivy.Server when this connection is registered? This is where we register the API client or any other services that are needed to use the connection. */
    public void RegisterServices(Server server)
    {
        server.Services.Add...
    }
    /* A method to test the connection and make sure the credentials are correctly set up. The config parameter provides access to user secrets and configuration. */
    public Task<(bool ok, string? message)> TestConnection(IConfiguration config);
}

public record ConnectionEntity(string Singular, string Plural);
```

```csharp
namespace Ivy;

public interface IHaveSecrets
{
    public Secret[] GetSecrets();
}

public sealed record Secret(string Key, string? Preset = null, bool Optional = false);
```

**Optional secrets:** If an API works without credentials (e.g., CoinGecko public API), use `new Secret("Key", Optional: true)`. Ivy skips optional secrets when checking for missing configuration at startup. The connection should still read the key from config and use it if present (for higher rate limits, etc.), but not require it.

#### Testing Guidelines

Tests should be written so an LLM reading the output can understand what went wrong. Use `ITestOutputHelper` to write diagnostic info (values returned, counts, property contents) in every test.

- **Unit tests** (no API key needed): `GetName`, `GetConnectionType`, `GetSecrets`, `GetEntities`, `GetContext` — validate connection class metadata.
- **Integration tests** (require API key): `TestConnection`, and tests for key read-only API methods. If the API key is missing, fail with a clear message like "ApiKey is not configured in user secrets. Cannot run API tests." Avoid test API calls that have side effects or cost money.

#### Program.cs Template

```csharp
var server = new Server();
server.UseCulture("en-US");
#if DEBUG
server.UseHotReload();
#endif
server.AddAppsFromAssembly();
server.AddConnectionsFromAssembly();
var chromeSettings = new ChromeSettings()
    .UseTabs(preventDuplicates: true);
server.UseChrome(chromeSettings);
await server.RunAsync();
```

#### App Guidelines

Create 1-3 Ivy apps in `Apps/` demonstrating the most common use cases. Apps should:
- Use the `[App(title: "...", icon: Icons.X)]` attribute (use constructor parameter syntax, not named properties for `icon`)
- Get the API client via `UseService<T>()`
- Handle loading states, errors, and empty states gracefully
- Use `UseQuery` hook for data-fetching apps (listing, browsing). For chat/streaming apps, use `UseState` with manual streaming — `UseQuery` is not suitable for long-running streamed responses
- Use standard Ivy widgets: `Layout`, `Text`, `Card`, `Chat`, `TableView`, `Callout`, etc.
- **Namespace collisions:** For LLM connections using `Microsoft.Extensions.AI`, beware that `ChatMessage` exists in both Ivy and `Microsoft.Extensions.AI`. Use type aliases to resolve (e.g. `using AiChatMessage = Microsoft.Extensions.AI.ChatMessage;`)

---

#### Create connection.yaml (all paths)

After the build is complete, create `connection.yaml` in the connection directory based on this template:

```yaml
name: Stripe # The name of the connection, usually the same as the service name
description: Connection to the Stripe API # A short description of the connection and what it does
tags:
  - payments
services:
  - StripeClient # The name of the main service registered in RegisterServices
secrets:
  - key: Stripe:ApiKey
    question: What is your Stripe API key?
nugets:
  - id: Stripe.Net # Nuget package id
    license: MIT # SPDX license identifier
    github: https://github.com/stripe/stripe-dotnet
    documentation: https://docs.stripe.com/api
references:
  - path: Ivy.Connections.Stripe/Connections/StripeConnection.cs
  - path: Ivy.Connections.Stripe/Apps/StripePaymentsApp.cs
    description: Browsable table of recent payments with status, amount, and currency via the Stripe Payments API.
help: | # Instructions on how to obtain the required secrets. Keep it focused: only a "Getting your API key" section with step-by-step instructions (sign up, navigate, create key, copy). Do NOT include sections about features, models, rate limits, pricing, etc.
```

Example tags: `payments`, `llm`, `crm`, `marketing`, `email`, `sms`, `analytics`, `developer`, `ecommerce`, `storage`

[ ] **Verify the connection via Ivy CLI** (these are separate commands — they cannot be combined in one invocation):

```bash
dotnet run -- --test-connection <ConnectionName>
dotnet run -- --describe-connection <ConnectionName>
```

- `--test-connection` must return `OK: ...` — if it reports missing secrets, the secret may need `Optional: true` or the user needs to configure credentials.
- `--describe-connection` must output the connection's name, type, namespace, context, secrets, and entities as YAML.
- Both commands must exit cleanly (exit code 0).

### 6. Testing Phase

Run the automated test suite via the PowerShell tool. Tests live in-place at `.ivy/tests/` inside the connection project directory (NOT in a temp directory).

```powershell
& "D:\Repos\_Personal\Scripts\AF2\CreateReferenceConnection\Tools\RunConnectionTests.ps1" -ServiceName "<ConnectionName>"
```

The test runner executes 4 phases:

1. **Build** — `dotnet build`
2. **Unit Tests** — `dotnet test` (xUnit tests in Tests/ folder)
3. **App Launch** — HTTP smoke test (start app, verify HTTP 200)
4. **Playwright E2E** — Agentic tests generated from app source code:
   - Discovers apps via `dotnet run --describe`
   - Reads app `.cs` files to understand UI elements (inputs, buttons, cards, etc.)
   - Generates per-app `.spec.ts` with real interactions (fill inputs, click buttons, verify results)
   - Takes numbered screenshots at each step
   - Captures console + backend logs
   - Checks for runtime errors both in logs and visually in screenshots

Tests output to `Ivy.Connections.<ConnectionName>/.ivy/tests/`:
- `*.spec.ts` — generated test specs
- `screenshots/` — numbered screenshots (01-initial-load.png, 02-after-search.png, etc.)
- `console.log`, `backend.log` — captured logs
- `report.md` — summary report

**IMPORTANT:** Add `.ivy/` to `.gitignore` in the connection project so test artifacts don't get committed.

[ ] Run the test suite and verify 4/4 pass
[ ] Review screenshots for visual quality and runtime errors
[ ] Check console.log and backend.log for exceptions

### 7. Fix Loop

If tests fail:
1. Analyze the failure — check screenshots, console.log, backend.log, playwright.log
2. Determine where the fix belongs:
   - **Test code** (wrong selectors, timing, rate limits) — fix the `.spec.ts` or the generator
   - **App code** (runtime errors, broken UI) — fix the `.cs` files
   - **Connection code** (API errors, auth issues) — fix the connection class
3. Apply fixes and rerun (max 5 rounds)
4. For external API rate limiting: tests should handle gracefully (accept Loading/error states)

### 8. Screenshot Review

After tests pass, review ALL screenshots in `.ivy/tests/screenshots/`. Check for:
- Runtime error indicators (error callouts, stack traces, "Something went wrong")
- Broken layouts or empty areas where content should appear
- Missing data or UI elements
- Visual quality and usability

Note any UX issues found for the user.

### Rules

- The agent MAY create/edit files under `D:\Repos\_Ivy\Ivy\connections\[ConnectionName]\`
- The agent must **ask the user for API keys/secrets** before proceeding with the build — never guess or skip secrets
- The agent must store secrets in **both** user secrets AND Azure Key Vault (`keyvault-ivy-dev`)
- Research must be thorough and accurate
- Follow the established format from existing research files
- Always recommend the best option with clear justification
- Include all relevant URLs and version information
- Make the "How to Obtain Secrets" section actionable and detailed
- If the service has multiple authentication methods, document all of them
- Note if certain features require paid plans or special access
