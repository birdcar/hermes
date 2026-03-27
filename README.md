# Hermes

Unified Docker images and deployment for **BirdClaw** (custom [OpenClaw](https://openclaw.ai)) and **BirdClip** (custom [Paperclip](https://github.com/paperclipai/paperclip)), deployed as a single [Coolify](https://coolify.io) service stack.

## Architecture

```
Coolify Service Stack
├── birdclaw          OpenClaw gateway + bun/gh/qmd    :18789
├── birdclaw_browser  Chromium CDP sidecar             :9222
├── birdclip          Paperclip server + UI            :3100
└── birdclip_db       PostgreSQL 17                    :5432
```

All four services share a Docker Compose network. Inter-service communication uses Docker DNS (`http://birdclaw:18789`, `http://birdclaw_browser:9222`, `http://birdclip:3100`). External access is routed through Coolify's Traefik proxy with TLS.

## Images

| Image | Base | Extras |
|-------|------|--------|
| `ghcr.io/birdcar/hermes/birdclaw` | `ghcr.io/openclaw/openclaw:latest` | bun.js, gh CLI, qmd (memory backend), pre-seeded config |
| `ghcr.io/birdcar/hermes/birdclip` | `node:lts-trixie-slim` | Paperclip built from source, claude-code CLI |

Images are built on push to `main` and weekly (Mondays 6am UTC) via GitHub Actions.

## Prerequisites

- [Coolify](https://coolify.io) v4 instance with Traefik proxy
- Wildcard DNS pointing to your Coolify server (e.g. `*.home.yourdomain.dev`)
- A Claude Max subscription (for `CLAUDE_CODE_OAUTH_TOKEN`)
- Discord bot token (if using Discord channel)
- ElevenLabs API key (if using TTS)

## Deployment

### 1. Create the Coolify service

```bash
# Base64-encode the compose file
COMPOSE_B64=$(base64 -w 0 < docker-compose.yml)

# Create the service via Coolify API
curl -X POST "https://your-coolify.example.com/api/v1/services" \
  -H "Authorization: Bearer YOUR_COOLIFY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Hermes\",
    \"project_uuid\": \"YOUR_PROJECT_UUID\",
    \"server_uuid\": \"YOUR_SERVER_UUID\",
    \"environment_name\": \"production\",
    \"docker_compose_raw\": \"${COMPOSE_B64}\"
  }"
```

### 2. Set environment variables

Set each variable via the Coolify API (values are plaintext -- Coolify encrypts at rest):

```bash
curl -X POST "https://your-coolify.example.com/api/v1/services/SERVICE_UUID/envs" \
  -H "Authorization: Bearer YOUR_COOLIFY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "CLAUDE_CODE_OAUTH_TOKEN", "value": "sk-ant-oat01-..."}'
```

Required variables (see `.env.example` for the full list):

| Variable | How to get it |
|----------|---------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Run `claude setup-token` from a machine with Claude Max |
| `OPENCLAW_GATEWAY_TOKEN` | `openssl rand -base64 48` |
| `OPENCLAW_HOOKS_TOKEN` | `openssl rand -hex 32` |
| `DISCORD_BOT_TOKEN` | Discord Developer Portal |
| `ELEVENLABS_API_KEY` | ElevenLabs dashboard |
| `BETTER_AUTH_SECRET` | `openssl rand -hex 32` |

### 3. Configure domains

In the Coolify dashboard (or via DB -- the API doesn't expose FQDN updates for sub-services):

| Service | Domain | Port |
|---------|--------|------|
| `birdclaw` | `birdclaw.home.yourdomain.dev` | 18789 |
| `birdclip` | `paperclip.home.yourdomain.dev` | 3100 |

Enable **"Connect to Predefined Network"** on the service for Traefik routing.

### 4. Deploy

```bash
curl -X POST "https://your-coolify.example.com/api/v1/services/SERVICE_UUID/start" \
  -H "Authorization: Bearer YOUR_COOLIFY_API_TOKEN"
```

### 5. Verify

```bash
curl -sf https://birdclaw.home.yourdomain.dev/healthz   # BirdClaw gateway
curl -sf https://paperclip.home.yourdomain.dev/health    # BirdClip server
```

## Customizing the OpenClaw config

The BirdClaw image includes a seed `openclaw.json` at `birdclaw/openclaw.json`. On first boot, this is copied to the config volume. After that, the volume-mounted config takes precedence.

To edit the live config:

```bash
docker exec -it BIRDCLAW_CONTAINER vi /home/node/.openclaw/openclaw.json
docker restart BIRDCLAW_CONTAINER
```

Key sections to customize:
- `channels.discord` -- guild IDs, user allowlists
- `agents.defaults.model` -- default model
- `messages.tts` -- voice provider and voice ID
- `memory` -- qmd backend settings
- `plugins.load.paths` -- extension directories

Sensitive values (API keys, tokens) should be passed as environment variables, not baked into the config.

## Host Node Setup (optional)

An OpenClaw "node" lets BirdClaw agents execute commands on the Docker host (diagnostics, Docker management, Tailscale, etc.), gated by an exec-approval allowlist.

### Install

```bash
# Install openclaw CLI
bun install -g openclaw

# Install the domain-restricted curl wrapper
sudo install -m 755 host/homelab-curl /usr/local/bin/homelab-curl
mkdir -p ~/.config/homelab-curl
cp host/allowed-domains.json ~/.config/homelab-curl/

# Configure exec approvals
mkdir -p ~/.openclaw
cp host/exec-approvals.json ~/.openclaw/

# Install systemd user service
mkdir -p ~/.config/systemd/user ~/.config/environment.d
cp host/birdclaw-node.service ~/.config/systemd/user/
echo 'OPENCLAW_GATEWAY_TOKEN=YOUR_TOKEN' > ~/.config/environment.d/birdclaw.conf
systemctl --user daemon-reload
systemctl --user enable --now birdclaw-node.service
```

### Pair the node

```bash
# From inside the BirdClaw container, approve the pending pairing request
docker exec -it BIRDCLAW_CONTAINER openclaw devices approve --latest
```

### How exec approvals work

| Setting | Value | Effect |
|---------|-------|--------|
| `security` | `allowlist` | Only allowlisted commands auto-execute |
| `ask` | `on-miss` | Commands not in the allowlist prompt for approval |
| `askFallback` | `deny` | If approval UI unavailable, block the command |

Allowlisted commands run automatically. Everything else prompts you. "Always allow" grows the list over time. Raw `curl` is deliberately excluded -- agents use `homelab-curl` which validates target domains first.

## Gotchas

- **GHCR package visibility**: Making the repo public does NOT make existing packages public. Each package must be set to public individually at `github.com/users/YOU/packages/container/PACKAGE/settings`.
- **Coolify `SERVICE_FQDN_*` vars**: These do NOT include the `https://` protocol prefix. Use `SERVICE_URL_*` or hardcode URLs when an app requires a full URL.
- **Coolify env var API**: Use `PATCH /api/v1/services/{uuid}/envs` with `{"key":"...","value":"..."}` to update. The PATCH goes to the **collection** endpoint, not individual env var UUIDs. Values are plaintext; Coolify encrypts internally.
- **Agent sandbox**: Requires Docker inside the container. The upstream OpenClaw image doesn't include Docker, so `sandbox.mode` should be `"off"` unless you add Docker-in-Docker to the Dockerfile.
- **Browser CDP port**: The `coollabsio/openclaw-browser` image exposes CDP on port 9222. The `BROWSER_CDP_URL` in the compose uses the service name `birdclaw_browser`.

## Volumes

| Volume | Mount | Contains | Backup priority |
|--------|-------|----------|----------------|
| `birdclaw-config` | `/home/node/.openclaw` | openclaw.json, credentials, sessions | High |
| `birdclaw-workspace` | `/home/node/.openclaw/workspace` | Agent memory, persona, skills | Medium |
| `birdclaw-extensions` | `/home/node/.openclaw/extensions` | Installed plugins | Low (re-installable) |
| `birdclaw-browser-data` | `/config` | Chromium profile | Low |
| `birdclip-data` | `/paperclip` | Paperclip config, encryption keys | High |
| `birdclip-pgdata` | `/var/lib/postgresql/data` | Paperclip database | High |
