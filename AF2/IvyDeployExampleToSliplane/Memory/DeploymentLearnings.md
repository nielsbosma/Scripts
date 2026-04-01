# Deployment Learnings

## csproj ProjectReference to PackageReference Conversion

Agent-created projects use local `ProjectReference` paths (e.g. `D:\Repos\_Ivy\Ivy-Framework\src\Ivy\Ivy.csproj`). These must be converted to NuGet `PackageReference` for Docker builds. Reference the existing `project-demos/helloworld/Helloworld.csproj` as a template.

## Sliplane Service Creation

- `--public` flag requires `--protocol http` to be specified
- The word "excel" in a service name causes a 500 error. Workaround: omit "excel" from the name (e.g. `ivy-agent-demos-formula-explainer` instead of `ivy-agent-demos-excel-formula-explainer`)
- Service creation can return persistent 500 errors during Sliplane API outages/instability. These are not related to name, server, or payload — the entire service creation endpoint goes down. Retrying after several minutes (2-5 min) usually resolves it.
- Service creation returns "Dockerfile not found" (400) when the root Dockerfile is absent. This is distinct from the 500 errors.

### dockerfilePath API Bug (as of 2026-03-23, API v0.3.1)

The Sliplane API returns HTTP 500 when `dockerfilePath` is included in a **service creation** (POST) request. **Workaround:**
1. Add a temporary Dockerfile at the repo root, push it
2. Create the service without `dockerfilePath` (uses root Dockerfile by default)
3. PATCH the service to set the correct `dockerfilePath` and `dockerContext`
4. Remove the temporary root Dockerfile, push again (triggers auto-deploy with correct config)

The PATCH endpoint accepts `dockerfilePath` without issues.

### Timing: Wait After Push Before Service Creation

After pushing the root Dockerfile, wait **at least 15 seconds** before calling the service creation API. The API clones the repo during creation — if the Dockerfile hasn't synced from GitHub yet, it returns 500 (not 400 "Dockerfile not found"). The 400 only appears when the Dockerfile is genuinely absent.

### Concurrent Agent Sessions

When multiple agent sessions deploy simultaneously, they compete over the root Dockerfile and trigger many auto-deploy builds. The root Dockerfile may be removed by another session between your push and service creation. Always verify the Dockerfile exists (pull first) before creating.

## SetMeta Methods Availability

- `SetMetaTitle` and `SetMetaDescription` work with Ivy 1.2.23+
- `SetMetaGitHubUrl` is NOT available in Ivy 1.2.34 — comment it out with a TODO

## Missing API Types in Ivy NuGet

- `HoverEffect` enum is not available in Ivy 1.2.34. Remove `.Hover()` calls that use it rather than commenting out, as they are non-essential styling.

## Slack Notification

- The Slack profile "state-of-ivy-agent" no longer exists (as of 2026-03-30)
- Use "done-by-niels" profile instead

## Sliplane Deploy Command

The `services deploy` POST endpoint requires an empty JSON body `{}`, not null/no-body. The CLI sends null when no `--tag` is provided, which causes a 400 error. Use curl directly as workaround.

## Sliplane CLI Flags

- The CLI uses `--repo` (not `--repo-url`) for repository URL
- The CLI uses `--auto-deploy` (not `--auto-deploy true`)

## Sliplane IDs

- **Project "Ivy-Examples-Agent-Generated":** `project_c1m7gor0293z`
- **Server "ivy-studio-demo":** `server_335oeo4g3cbd` (dedicated-base)
- **Server "ivy-hosting-1":** `server_fgn4nsi1p36w` (dedicated-large)

## Robocopy from Bash

Robocopy works from bash via `powershell -Command "robocopy ..."`. Direct robocopy from bash has escaping issues with /E flag. Watch for duplicate files — robocopy may copy files to root that also exist in subdirectories (e.g. CompressorApp.cs at root AND in Apps/).
