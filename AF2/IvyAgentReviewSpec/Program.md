# IvyAgentReviewSpec

Review an Ivy Agent project against its spec and produce a result report.

## Context

Args contains the path to the project folder (e.g. `D:\Temp\IvyAgentRun\ByteForge.UrlCraft`).

Read about the important paths and files in ../.shared/Paths.md

## Execution Steps

### 1. Locate Spec

- Read `.ivy\spec.md` in the project folder specified in Args
- If the spec file doesn't exist, report an error and stop

### 2. Parse Requirements

From the spec, extract:
- **Apps**: app names, files, features, UI layout requirements
- **Connections**: connection implementations expected
- **General requirements**: any other specifications (namespace, icon, group, layout, etc.)

### 3. Inventory the Implementation

Scan the project folder to understand what was actually built:
- List all `.cs` files and their locations
- Read each source file to understand what was implemented
- Check `Program.cs` for app/connection registrations
- Check the `.csproj` for project configuration and dependencies
- Check for `GlobalUsings.cs`

### 4. Review Against Spec

For each requirement in the spec, assess:

- **Implemented**: The feature exists and matches the spec
- **Partial**: The feature exists but is incomplete or deviates from spec
- **Missing**: The feature was not implemented
- **Extra**: Something was built that wasn't in the spec (note but don't penalize)

Specific checks:
- All specified apps exist in the correct file paths
- All specified connections exist
- Namespace conventions match
- UI layout matches what was specified
- Features listed in the spec are present in the code
- Icon, Group, and Layout metadata match the spec

### 5. Run --describe, --describe-connection, --test-connection

> dotnet run --describe
apps:
- name: App Not Found
  id: $error-not-found
  isVisible: false
- name: Mermaid Editor
  id: mermaid-editor
  isVisible: true
- name: Chrome
  id: $chrome
  isVisible: false
connections: []
secrets: []
services:
- serviceType: Ivy.ServerArgs
  implementationType: Ivy.ServerArgs
  lifetime: Singleton
  description:
- serviceType: Microsoft.Extensions.Configuration.IConfiguration
  implementationType: Microsoft.Extensions.Configuration.ConfigurationRoot
  lifetime: Singleton
  description:
- serviceType: Ivy.IThemeService
  implementationType: Ivy.ThemeService
  lifetime: Singleton
  description:

>dotnet run --decribe-connection <ConnectionName>
>dotnet run --test-connection <ConnectionName>

### 6. Generate Result

Write the result to `.ivy\review-spec.md` in the project folder.

Format:

```markdown
# Spec Review: [Project Name]

## Summary

| Status | Count |
|--------|-------|
| Implemented | X |
| Partial | X |
| Missing | X |

## Requirements

### [App/Connection Name]

| Requirement | Status | Notes |
|-------------|--------|-------|
| File: `Apps\XxxApp.cs` | ✅ Implemented | |
| Namespace: `Xxx.Yyy.Apps` | ✅ Implemented | |
| Feature: URL encoding | ✅ Implemented | |
| Feature: Clipboard copy | ⚠️ Partial | Missing toast notification |
| Feature: Dark mode | ❌ Missing | |

### General

| Requirement | Status | Notes |
|-------------|--------|-------|
| Icon: `Link` | ✅ Implemented | |
| Group: `Apps` | ✅ Implemented | |

## Extra Items

- [List anything built that wasn't in the spec]

## Overall Assessment

[Brief paragraph: did the implementation meet the spec? What are the gaps?]
```

### Rules

- Do NOT modify any source code — this is a read-only review
- Be precise: quote the spec requirement and the actual implementation
- Keep the result concise and actionable
