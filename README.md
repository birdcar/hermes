# Hermes

Unified Docker images and deployment for **BirdClaw** (custom OpenClaw) and **BirdClip** (custom Paperclip), deployed as a single Coolify service stack.

## Architecture

```
Coolify Service Stack
├── birdclaw        → ghcr.io/birdcar/hermes/birdclaw (OpenClaw + bun/gh/qmd)
├── birdclaw_browser → coollabsio/openclaw-browser (Chromium CDP sidecar)
├── birdclip        → ghcr.io/birdcar/hermes/birdclip (Paperclip server)
└── birdclip_db     → postgres:17-alpine
```

## Images

| Image | Base | Purpose |
|-------|------|---------|
| `ghcr.io/birdcar/hermes/birdclaw` | `ghcr.io/openclaw/openclaw` | OpenClaw with bun.js, gh CLI, qmd, pre-seeded config |
| `ghcr.io/birdcar/hermes/birdclip` | `node:lts-trixie-slim` | Paperclip built from source |

Images are built automatically on push to `main` and weekly (Mondays 6am UTC) via GitHub Actions.

## Deployment

See `docker-compose.yml` for the Coolify-ready compose file. Copy `.env.example` to configure credentials.

## Host Tooling

The `host/` directory contains tools for running an OpenClaw node on the Coolify host:

- `homelab-curl` -- Domain-restricted curl wrapper
- `exec-approvals.json` -- Command allowlist for the host node
- `birdclaw-node.service` -- systemd user service for the node
