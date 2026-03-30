# CLAUDE.md

## What is this repo?

Hermes is a monorepo containing custom Docker images and deployment config for two AI services:

- **BirdClaw** (`birdclaw/`) -- Custom OpenClaw image extending `ghcr.io/openclaw/openclaw:latest` with bun.js, gh CLI, qmd memory backend, and a pre-seeded config
- **BirdClip** (`birdclip/`) -- Custom Paperclip image built from source via `paperclipai/paperclip`

These deploy as a single Coolify Docker Compose service with 4 containers: birdclaw, birdclaw_browser (Chromium CDP sidecar), birdclip, birdclip_db (PostgreSQL).

## Repo structure

```
birdclaw/
  Dockerfile          # Extends ghcr.io/openclaw/openclaw:latest
  entrypoint.sh       # Seeds config on first run, chains to upstream entrypoint
  openclaw.json       # Seed config (only used if no config exists in volume)
birdclip/
  Dockerfile          # Multi-stage build of Paperclip from source
  entrypoint.sh       # Startup wrapper
docker-compose.yml    # Coolify-ready compose (4 services, 9 named volumes)
.env.example          # Required environment variables
security/
  SECURITY.md         # Agent cognitive inoculation (trust boundaries)
  SECURITY.local.md   # Homelab-specific agent safety rules
host/
  homelab-curl        # Domain-restricted curl wrapper for host node
  allowed-domains.json
  exec-approvals.json # Host node command allowlist
  birdclaw-node.service  # systemd user service for OpenClaw host node
.github/workflows/
  build-images.yml    # Builds both images to GHCR on push + weekly
```

## Coolify API patterns

When making changes to the Coolify service programmatically:

- Create service: `POST /api/v1/services` with base64-encoded `docker_compose_raw`
- Create env var: `POST /api/v1/services/{uuid}/envs` with `{"key":"...","value":"..."}` — returns 409 if key already exists
- Update env var: `PATCH /api/v1/services/{uuid}/envs` with same body — this is the **collection** endpoint, NOT an individual UUID path
- Update compose: `PATCH /api/v1/services/{uuid}` with `{"docker_compose_raw":"<base64>"}`
- `SERVICE_FQDN_*` variables do NOT include `https://`; use `SERVICE_URL_*` when the app needs a full URL

**Never write directly to the Coolify database.** Coolify encrypts env var values with Laravel's Encrypter. Direct DB writes corrupt the service (causes "payload is invalid" in the dashboard). Always use the API.

## Agent-specific gotchas

**Agent sandbox mode** — Keep `agents.defaults.sandbox.mode` set to `"off"`. The upstream OpenClaw image does not include Docker, so sandboxed execution will fail. Only enable if Docker-in-Docker is added to the Dockerfile.

**qmd package name** — The npm package is `@tobilu/qmd`, not bare `qmd`. The binary is symlinked to `/usr/local/bin/qmd` because `bun install -g` puts binaries under `/root`, which is not on the `node` user's PATH.

**The `coollabsio/openclaw` image is different from `ghcr.io/openclaw/openclaw`** — The coollabsio wrapper runs as root, uses `/data/` paths, and adds an nginx proxy on port 8080. The upstream image runs as `node`, uses `/home/node/.openclaw/` paths, and exposes the gateway directly. This repo uses the upstream image.

## When modifying

- Edit `birdclaw/openclaw.json` for config changes that should apply to fresh deployments. Existing deployments use the volume-mounted config; update those live via `docker exec`.
- After pushing to `main`, CI builds both images and triggers a Coolify redeploy. Pull the new images on the Coolify host and restart the service if the auto-deploy doesn't fire.
- The `security/` files are copied into the BirdClaw workspace volume post-deploy. They are not baked into the image.
