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
docker-compose.yml    # Coolify-ready compose (4 services, 6 named volumes)
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

## Key technical details

### BirdClaw Dockerfile
- Base: `ghcr.io/openclaw/openclaw:latest` (runs as `node` uid 1000, workdir `/app`)
- Upstream entrypoint: `docker-entrypoint.sh` (standard Node image -- prepends `node` if first arg isn't a command)
- Upstream CMD: `["node", "openclaw.mjs", "gateway", "--allow-unconfigured"]`
- Our entrypoint seeds `openclaw.json` on first run, then chains to the upstream entrypoint
- Seed config lives at `/home/node/.openclaw.seed/openclaw.json`; volume-mounted config at `/home/node/.openclaw/openclaw.json` takes precedence after first boot
- `EXTRA_APT_PACKAGES` build arg allows injecting additional packages without modifying the Dockerfile

### BirdClip Dockerfile
- Multi-stage build: clones `paperclipai/paperclip` at build time with `PAPERCLIP_REF` arg (default: `master`)
- Runs as `node` uid 1000, port 3100
- Data volume at `/paperclip`

### Docker Compose
- All services on the same default network; inter-service DNS uses service names
- `birdclaw` gateway exposed on `127.0.0.1:18789` for host node access
- Browser sidecar uses `coollabsio/openclaw-browser:latest` with CDP on port 9222
- `SERVICE_FQDN_BIRDCLIP_3100` is a Coolify magic variable that auto-resolves to the configured FQDN

### Coolify API patterns
- Create service: `POST /api/v1/services` with base64-encoded `docker_compose_raw`
- Set env var: `PATCH /api/v1/services/{uuid}/envs` with `{"key":"...","value":"..."}` (collection endpoint, NOT individual UUID path)
- Create env var: `POST /api/v1/services/{uuid}/envs` with same body (returns 409 if key exists)
- Update compose: `PATCH /api/v1/services/{uuid}` with `{"docker_compose_raw":"<base64>"}`
- Coolify `SERVICE_FQDN_*` variables do NOT include `https://`; use `SERVICE_URL_*` or hardcode when the app needs a full URL

## Things to watch out for

- **Never write directly to the Coolify database.** Coolify encrypts env var values with Laravel's Encrypter. Direct DB writes bypass encryption and corrupt the service, causing "payload is invalid" errors in the dashboard. Always use the API.
- **Agent sandbox requires Docker inside the container.** The upstream OpenClaw image does not include Docker. Keep `agents.defaults.sandbox.mode` set to `"off"` unless Docker-in-Docker is added to the Dockerfile.
- **GHCR package visibility is separate from repo visibility.** Making the repo public does not make existing packages public. Each must be toggled individually in GitHub package settings.
- **Browser CDP port is 9222**, not 9223. The `coollabsio/openclaw-browser` image exposes Chrome's debug port directly on 9222.
- **The `coollabsio/openclaw` image (one-click) is different from `ghcr.io/openclaw/openclaw`.** The coollabsio wrapper runs as root, uses `/data/` paths, and adds an nginx proxy on port 8080. The upstream image runs as `node`, uses `/home/node/.openclaw/` paths, and exposes the gateway directly. This repo uses the upstream image.

## When modifying

- Edit `birdclaw/openclaw.json` for config changes that should apply to fresh deployments. Existing deployments use their volume-mounted config; update those live via `docker exec`.
- After pushing to `main`, CI builds both images. Pull the new images on the Coolify host and restart the service to pick up changes.
- The `security/` files are copied into the BirdClaw workspace volume post-deploy. They are not baked into the image.
