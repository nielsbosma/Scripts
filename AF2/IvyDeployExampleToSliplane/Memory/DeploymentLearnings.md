# Deployment Learnings

## csproj ProjectReference to PackageReference Conversion

Agent-created projects use local `ProjectReference` paths (e.g. `D:\Repos\_Ivy\Ivy-Framework\src\Ivy\Ivy.csproj`). These must be converted to NuGet `PackageReference` for Docker builds. Reference the existing `project-demos/helloworld/Helloworld.csproj` as a template.

## Sliplane Service Creation

- `--public` flag requires `--protocol http` to be specified
- Server `server_fgn4nsi1p36w` (ivy-hosting-1) returned 500 errors on service creation; `server_335oeo4g3cbd` (ivy-studio-demo) works
- The Dockerfile path should be the full path from repo root: `agent-demos/<name>/Dockerfile`
- Docker context should also be from repo root: `agent-demos/<name>`

## Sliplane IDs

- **Project "Ivy-Examples-Agent-Generated":** `project_c1m7gor0293z`
- **Server "ivy-studio-demo":** `server_335oeo4g3cbd`
- **Server "ivy-hosting-1":** `server_fgn4nsi1p36w` (may have issues with service creation)
