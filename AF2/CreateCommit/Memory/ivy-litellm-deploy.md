---
name: Ivy-LiteLLM deployment flow
description: How infra vs container deploy works in Ivy-LiteLLM, and the activeRevisionsMode gotcha
type: project
---

Ivy-LiteLLM has two workflows:
- `infra.yml` (workflow_dispatch) — deploys Bicep/ARM template (main.json), KeyVault secrets, config.yaml
- `deploy.yml` (on release published) — deploys a new container revision with blue-green traffic shifting

**Critical:** If `activeRevisionsMode` is `Multiple`, the infra workflow alone can leave the app with no traffic-bearing revision. A release (deploy) must follow infra changes that affect the container app.

**Why:** Learned 2026-03-19 when switching from Single to Multiple mode caused downtime until a release was created.

**How to apply:** After running infra workflow for container-affecting changes, always create a release to trigger deploy. Use `gh release list` (not `git tag`) to find the latest version number.
