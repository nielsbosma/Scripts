# IvyDeployExampleToSliplane

Deploy an Ivy project to Sliplane as an agent demo in the Ivy-Examples repository.

**Args:** `<project-path>` - The path to the dotnet project to deploy.

## Constants

- **Ivy-Examples repo:** `D:\Repos\_Ivy\Ivy-Examples`
- **Agent demos folder:** `D:\Repos\_Ivy\Ivy-Examples\agent-demos`
- **Sliplane CLI:** `dotnet run --project D:/Repos/_Personal/Sliplane.Console/src --`
- **Sliplane project name:** `Ivy-Examples-Agent-Generated`
- **Sliplane project ID:** `project_c1m7gor0293z`
- **Sliplane server ID:** `server_335oeo4g3cbd` (ivy-studio-demo)
- **GitHub repo:** `Ivy-Interactive/Ivy-Examples`

## Execution Steps

### 1. Parse Args

Extract the `<project-path>` from Args. Resolve it to an absolute path. Verify the path exists and contains a `.csproj` file. Extract the project name from the `.csproj` filename.

### 2. Ensure Ivy-Examples is up to date

```powershell
cd D:\Repos\_Ivy\Ivy-Examples
git fetch origin
git status
```

If behind origin/main, pull. If there are uncommitted changes, warn the user and ask whether to proceed.

### 3. Create agent-demos folder

- Derive a human-friendly kebab-case name from the project: drop any `Test.` prefix, split on PascalCase boundaries, lowercase, join with `-`. Example: `Test.EmojiVotingBooth` → `emoji-voting-booth`
- Target: `D:\Repos\_Ivy\Ivy-Examples\agent-demos\<name>`
- Check if the folder already exists:
  - If YES: warn the user that this looks like a redeployment and ask to confirm before overwriting
  - If NO: create it

### 4. Copy project files and fix csproj

Copy all files from `<project-path>` to the target folder. **Exclude:**
- `.ivy/` folder
- `obj/` folders
- `bin/` folders
- `.vs/` folder

Use robocopy or PowerShell Copy-Item with appropriate exclusions.

**IMPORTANT:** After copying, check the `.csproj` file for local `ProjectReference` entries (paths like `D:\Repos\_Ivy\Ivy-Framework\...`). These won't work in Docker. Convert them to NuGet `PackageReference` entries. Use `project-demos/helloworld/Helloworld.csproj` as a reference template. Find the latest Ivy version with `dotnet package search Ivy --source https://api.nuget.org/v3/index.json --exact-match`.

### 4.5. Set meta tags in Program.cs

After copying and fixing the csproj, modify `Program.cs` in the target folder to add HTML meta tags for the deployed app.

1. Read `<target-folder>/Program.cs`
2. Find the line containing `new Server()` assignment
3. Insert these three lines immediately after it:

```csharp
server.SetMetaTitle("<Title>");
server.SetMetaDescription("<Description>");
server.SetMetaGitHubUrl("https://github.com/Ivy-Interactive/Ivy-Examples/tree/main/agent-demos/<name>");
```

- **Title**: Human-friendly project name, title-cased with spaces (e.g. "Emoji Voting Booth")
- **Description**: Same 1-2 sentence description used for the README
- **GitHubUrl**: Points to the agent-demos subfolder in the Ivy-Examples repo

If the `Program.cs` already contains any of these calls, skip the ones that already exist.

> **Note:** These SetMeta methods may not be available in the latest published NuGet version. The local build step (7.5) will catch this. If they fail to compile, comment them out.

### 5. Create Dockerfile and .dockerignore

**Dockerfile** - Model after existing project-demos. Template:

```dockerfile
# Base runtime image
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
WORKDIR /app
EXPOSE 80

# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src

# Copy and restore
COPY ["<ProjectName>.csproj", "./"]
RUN dotnet restore "<ProjectName>.csproj"

# Copy everything and build
COPY . .
RUN dotnet build "<ProjectName>.csproj" -c $BUILD_CONFIGURATION -o /app/build

# Publish stage
FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "<ProjectName>.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=true

# Final runtime image
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .

# Set environment variables
ENV PORT=80
ENV ASPNETCORE_URLS="http://+:80"

# Run the executable
ENTRYPOINT ["dotnet","./<ProjectName>.dll"]
```

Replace `<ProjectName>` with the actual .csproj name (without extension).

**.dockerignore** - Use standard template:

```
**/.dockerignore
**/.env
**/.git
**/.gitignore
**/.project
**/.settings
**/.toolstarget
**/.vs
**/.vscode
**/.idea
**/*.*proj.user
**/*.dbmdl
**/*.jfm
**/azds.yaml
**/bin
**/charts
**/docker-compose*
**/Dockerfile*
**/node_modules
**/npm-debug.log
**/obj
**/secrets.dev.yaml
**/values.dev.yaml
LICENSE
README.md
```

### 6. Collect dotnet user-secrets and create README

Run from the `<project-path>`:

```powershell
dotnet user-secrets list --project "<project-path>"
```

This outputs lines like `KEY = VALUE`. Parse and store all key-value pairs — both keys and values will be needed in step 8.

If the command fails with "Could not find the global property 'UserSecretsId'" then the project has no secrets configured.

Create a `README.md` in the target folder. Before writing it, read the main source files (e.g., `Program.cs`, app classes in `Apps/` folder) from `<project-path>` to understand what the app does and write a short 1-2 sentence description.

Use this template:

```markdown
# <Project Name>

<Short 1-2 sentence description of what the app does, derived from reading the source code.>

![Screenshot](screenshot.png)

Web application created using [Ivy](https://github.com/Ivy-Interactive/Ivy).

## Required Secrets

The following environment variables / user-secrets are required:

| Key | Description | How to obtain |
|-----|-------------|---------------|
| ... | ... | ... |

For each secret, research the key name to determine what service it belongs to and populate the "How to obtain" column with a brief instruction, such as:

- **OpenAI:ApiKey** - Create an API key at [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
- **Anthropic:ApiKey** - Create an API key at [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys)
- **Google:ApiKey** - Create an API key in the [Google AI Studio](https://aistudio.google.com/apikey)
- **Azure:ConnectionString** - Find in Azure Portal under the resource's "Access keys" blade
- **Unsplash:AccessKey** - Register an app at [unsplash.com/developers](https://unsplash.com/developers)

For less common or project-specific secrets, read the source code to understand what service the secret connects to and provide the relevant sign-up or dashboard URL.

Set these as secret environment variables when deploying to Sliplane.

## Live Demo

<https://ivy-agent-demos-<name>.sliplane.app>

## Run

```
dotnet watch
```

## Deploy

```
ivy deploy
```
```

If no secrets exist, state "No secrets required for this project." instead of the table.

**Screenshot selection:** After creating the README, check if `<project-path>/.ivy/tests/screenshots/` exists and contains images. If yes, select the best representative screenshot:
- Prefer a screenshot with "overview", "main", or "complete" in the name
- Otherwise, pick the one at roughly 60% through the sorted list (to avoid initial loading states)
- Copy the selected screenshot to the target folder as `screenshot.png`

If no screenshots exist, remove the `![Screenshot](screenshot.png)` line from the README.

### 7. Push to GitHub

```powershell
cd D:\Repos\_Ivy\Ivy-Examples
git add agent-demos/<name>/README.md agent-demos/<name>/screenshot.png agent-demos/<name>
git commit -m "Add <name> agent demo"
git push origin main
```

### 7.5. Local build validation

Before deploying to Sliplane, verify the project builds successfully with the NuGet package references:

```powershell
cd D:\Repos\_Ivy\Ivy-Examples\agent-demos\<name>
dotnet build -c Release
```

If the build fails due to missing `SetMeta*` methods (SetMetaTitle, SetMetaDescription, SetMetaGitHubUrl), these are not yet published in the latest Ivy NuGet package. Comment out the failing lines in Program.cs with `// TODO: Uncomment when Ivy publishes SetMeta methods`, commit and push the fix, then proceed.

If the build fails for other reasons, diagnose and fix before continuing.

### 8. Deploy to Sliplane

Use the project ID and server ID from Constants above. No need to list projects/servers each time.

Create the service (note: `--protocol http` is required when using `--public`, and `--dockerfile` must be the full path from repo root).

If user-secrets were found in step 6, append `--secret-env KEY=VALUE` flags for each secret. Use the actual values from `dotnet user-secrets list` — these are the developer's local secrets and should be carried over to the deployment. Dotnet user-secrets use `:` as a section separator (e.g. `OpenAI:ApiKey`) but environment variables use `__` (double underscore). Convert the keys: replace `:` with `__` in the `--secret-env` flag. Example: secret `OpenAI:ApiKey = sk-123` becomes `--secret-env OpenAI__ApiKey=sk-123`.

**KNOWN BUG (API v0.3.1):** The Sliplane API returns HTTP 500 when `dockerfilePath` is included in service creation, and also when `healthcheck` is omitted.

**Workaround:**
1. Ensure a temporary Dockerfile exists at the Ivy-Examples repo root, commit and push
2. Create the service via curl WITHOUT `dockerfilePath`/`dockerContext` but WITH `healthcheck`. Use server `server_fgn4nsi1p36w` (ivy-hosting-1) — the demo server is at capacity:
```bash
curl -s -X POST "https://ctrl.sliplane.io/v0/projects/project_c1m7gor0293z/services" \
  -H "Authorization: Bearer $SLIPLANE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name":"ivy-agent-demos-<name>","serverId":"server_fgn4nsi1p36w","deployment":{"url":"https://github.com/Ivy-Interactive/Ivy-Examples","branch":"main","autoDeploy":true},"network":{"public":true,"protocol":"http"},"healthcheck":"/"}'
```
3. PATCH the service to set the correct paths:
```bash
curl -s -X PATCH "https://ctrl.sliplane.io/v0/projects/project_c1m7gor0293z/services/<SERVICE_ID>" \
  -H "Authorization: Bearer $SLIPLANE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"deployment":{"url":"https://github.com/Ivy-Interactive/Ivy-Examples","branch":"main","dockerfilePath":"agent-demos/<name>/Dockerfile","dockerContext":"agent-demos/<name>","autoDeploy":true}}'
```
4. Remove the temporary root Dockerfile, commit and push (triggers auto-deploy with correct config)
5. To add secret env vars, include `"env":[{"key":"KEY","value":"VALUE","secret":true}]` in the PATCH body

If the service already exists (redeployment), trigger a deploy:
```bash
curl -s -X POST "https://ctrl.sliplane.io/v0/projects/project_c1m7gor0293z/services/<SERVICE_ID>/deploy" \
  -H "Authorization: Bearer $SLIPLANE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{}'
```

If the service already exists (redeployment), trigger a deploy instead:

```powershell
dotnet run --project D:/Repos/_Personal/Sliplane.Console/src -- services deploy `
  --project-id project_c1m7gor0293z `
  --service-id <SERVICE_ID>
```

To find the service ID for redeployment:
```powershell
dotnet run --project D:/Repos/_Personal/Sliplane.Console/src -- services list --project-id project_c1m7gor0293z
```

### 9. Wait for deployment

Check service events/logs to verify the deployment succeeded:

```powershell
dotnet run --project D:/Repos/_Personal/Sliplane.Console/src -- services events `
  --project-id project_c1m7gor0293z `
  --service-id <SERVICE_ID>
```

Wait ~60 seconds after the push for the build to complete before checking events.

Report the service URL to the user when ready.

### 9.5. Update README with live URL

After deployment is verified, update the README with the actual deployed URL:

1. Read back the service URL from the deployment output (format: `https://ivy-agent-demos-<name>.sliplane.app`)
2. Replace the placeholder `<name>` in the `## Live Demo` URL in the README.md with the actual service name
3. Commit and push the update:

```powershell
cd D:\Repos\_Ivy\Ivy-Examples
git add agent-demos/<name>/README.md
git commit -m "Update <name> README with live demo link"
git push origin main
```

### 10. Notify Slack

Post a message to Slack about the deployed app:

```powershell
cd D:/Repos/_Personal/Notify.Console/src && dotnet run -- slack state-of-ivy-agent --message "Deployed <name>: https://ivy-agent-demos-<name>.sliplane.app | GitHub: https://github.com/Ivy-Interactive/Ivy-Examples/tree/main/agent-demos/<name>"
```

Include the app name, deployed URL, and GitHub README link in the message.
