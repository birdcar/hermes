# Architecture

## BirdClaw

**Base image:** `ghcr.io/openclaw/openclaw:latest`

Runs as `node` uid 1000, workdir `/app`. The upstream entrypoint is `docker-entrypoint.sh` (standard Node image behavior — prepends `node` if the first argument isn't an executable). The upstream CMD is `node openclaw.mjs gateway --allow-unconfigured`.

The BirdClaw entrypoint (`birdclaw/entrypoint.sh`) does two things before handing off to the upstream:

1. If no `openclaw.json` exists in the config volume, copies the seed config from `/home/node/.openclaw.seed/openclaw.json`
2. If the qmd memory collection doesn't exist in the workspace, initializes it (`qmd collection add` + `qmd embed`)

The seed config lives at `/home/node/.openclaw.seed/openclaw.json`. Once the volume has a live config at `/home/node/.openclaw/openclaw.json`, the seed is never referenced again.

**Build arg:** `EXTRA_APT_PACKAGES` — injects additional apt packages without modifying the Dockerfile.

**Added tools:**
- `bun` — installed globally to `/usr/local/bun`, symlinked to PATH
- `gh` — GitHub CLI, installed from the official GitHub apt repo
- `jq` — JSON processor
- `qmd` — `@tobilu/qmd` (hybrid BM25 + vector memory backend). `bun install -g` puts binaries under `/root`, which isn't on the `node` user's PATH, so the binary is symlinked to `/usr/local/bin/qmd`
- Vulkan libraries (`libvulkan1`, `mesa-vulkan-drivers`, `vulkan-tools`) — for GPU-accelerated browser rendering via the DRI device passthrough

**Exposed ports:** 18789 (gateway), 18790 (reserved)

## BirdClip

**Base image:** `node:lts-trixie-slim` (multi-stage build)

The build stage clones `paperclipai/paperclip` at the ref specified by `PAPERCLIP_REF` (default: `master`) and builds all workspace packages. The production stage copies the built output, installs gh CLI, bun, and the following global npm packages: `@anthropic-ai/claude-code`, `@openai/codex`, `opencode-ai`.

Runs as `node` uid 1000, port 3100. `HOME` is set to `/paperclip` (the data volume) so Claude Code and gh credentials written to `$HOME` persist across restarts.

The entrypoint (`birdclip/entrypoint.sh`) pre-seeds Claude Code's onboarding flag to suppress the interactive wizard, then runs `npx paperclipai onboard --yes` on first boot if no config exists.

After first boot, create an admin invite with:

```bash
docker exec -it BIRDCLIP_CONTAINER npx paperclipai auth bootstrap-ceo
```

## Network topology

All four services share the Compose default network. Inter-service DNS uses service names:

| Consumer | Connects to | Address |
|----------|-------------|---------|
| birdclaw | Chromium CDP | `http://birdclaw_browser:9222` |
| birdclip | OpenClaw gateway | `http://birdclaw:18789` |
| birdclip | PostgreSQL | `postgres://paperclip:paperclip@birdclip_db:5432/paperclip` |

The `birdclaw` gateway is also bound to `127.0.0.1:18789` on the host for the optional host node connection. External traffic enters through Coolify's Traefik proxy.

## Volume layout

| Volume | Mount path | Service | Notes |
|--------|-----------|---------|-------|
| `birdclaw-config` | `/home/node/.openclaw` | birdclaw | Live openclaw.json, paired devices, sessions, credentials |
| `birdclaw-workspace` | `/home/node/.openclaw/workspace` | birdclaw | Agent persona files, memory, skills — not in repo |
| `birdclaw-extensions` | `/home/node/.openclaw/extensions` | birdclaw | Installed plugins |
| `birdclaw-browser-data` | `/config` | birdclaw_browser | Chromium profile |
| `birdclaw-gh-config` | `/home/node/.config/gh` | birdclaw | gh CLI auth |
| `birdclip-data` | `/paperclip` | birdclip | Config, encryption keys, `$HOME` for credentials |
| `birdclip-gh-config` | `/paperclip/.config/gh` | birdclip | gh CLI auth |
| `birdclip-pgdata` | `/var/lib/postgresql/data` | birdclip_db | Paperclip database |
| `birdclaw-qmd-cache` | `/home/node/.cache/qmd` | birdclaw | qmd embedding cache (persisted to avoid re-embedding on restart) |
