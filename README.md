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

All four services share a Docker Compose network. Inter-service communication uses Docker DNS (`http://birdclaw:18789`, `http://birdclaw_browser:9222`, `http://birdclip:3100`). No ports are exposed to the host -- external access goes through Coolify's Traefik proxy with TLS.

## Images

| Image | Base | Extras |
|-------|------|--------|
| `ghcr.io/birdcar/hermes/birdclaw` | `ghcr.io/openclaw/openclaw:latest` | bun.js, gh CLI, qmd (`@tobilu/qmd` -- hybrid BM25 + vector memory backend), pre-seeded config |
| `ghcr.io/birdcar/hermes/birdclip` | `node:lts-trixie-slim` | Paperclip built from source, claude-code CLI |

Images are built on push to `main` and weekly (Mondays 6am UTC) via GitHub Actions. After a successful build, CI joins your Tailscale network and triggers a Coolify redeploy automatically.

## Prerequisites

- [Coolify](https://coolify.io) v4 instance with Traefik proxy
- Wildcard DNS pointing to your Coolify server (e.g. `*.home.yourdomain.dev`)
- A Claude Max subscription (for `CLAUDE_CODE_OAUTH_TOKEN`)
- Discord bot token (if using Discord channel)
- ElevenLabs API key (if using TTS)
- A [Tailscale](https://tailscale.com) account (for CI auto-deploy)

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

Set each variable via the Coolify API. Use `POST` to create, `PATCH` to update. Both go to the **collection** endpoint (not individual env var UUIDs). Values are plaintext -- Coolify encrypts at rest.

```bash
# Create a new env var
curl -X POST "https://your-coolify.example.com/api/v1/services/SERVICE_UUID/envs" \
  -H "Authorization: Bearer YOUR_COOLIFY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "CLAUDE_CODE_OAUTH_TOKEN", "value": "sk-ant-oat01-..."}'

# Update an existing env var
curl -X PATCH "https://your-coolify.example.com/api/v1/services/SERVICE_UUID/envs" \
  -H "Authorization: Bearer YOUR_COOLIFY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "CLAUDE_CODE_OAUTH_TOKEN", "value": "new-value"}'
```

Required variables (see `.env.example` for the full list):

| Variable | How to get it | Used by |
|----------|---------------|---------|
| `CLAUDE_CODE_OAUTH_TOKEN` | `claude setup-token` on a machine with Claude Max | birdclaw, birdclip |
| `OPENCLAW_GATEWAY_TOKEN` | `openssl rand -base64 48` | birdclaw |
| `OPENCLAW_HOOKS_TOKEN` | `openssl rand -hex 32` | birdclaw, birdclip |
| `DISCORD_BOT_TOKEN` | Discord Developer Portal | birdclaw |
| `ELEVENLABS_API_KEY` | ElevenLabs dashboard | birdclaw |
| `BETTER_AUTH_SECRET` | `openssl rand -hex 32` | birdclip |
| `AUTH_USERNAME` | Your choice (Control UI login) | birdclaw |
| `AUTH_PASSWORD` | Your choice (Control UI login) | birdclaw |

### 3. Configure domains

In the Coolify dashboard, set FQDNs for the two web-facing services:

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

### 5. Pair the Control UI

After the first deploy, visit `https://birdclaw.home.yourdomain.dev`. The Control UI will show "pairing required." This is the normal device trust handshake:

1. Enter the websocket URL and gateway token in the browser UI
2. From the host, approve the pending pairing request:
   ```bash
   docker exec -it BIRDCLAW_CONTAINER openclaw devices approve --latest
   ```
3. Refresh the page -- you'll see the login screen
4. Log in with your `AUTH_USERNAME` / `AUTH_PASSWORD` credentials

Pairing is per-browser. Each new browser/device needs to be approved the same way.

### 6. Verify

```bash
curl -sf https://birdclaw.home.yourdomain.dev/healthz   # BirdClaw gateway
curl -sf https://paperclip.home.yourdomain.dev/health    # BirdClip server
```

## CI/CD Auto-Deploy

The GitHub Actions workflow builds both images, then joins your Tailscale network to trigger a Coolify redeploy. This requires:

1. A Tailscale OAuth client (create at [Tailscale Admin > Settings > Trust credentials](https://login.tailscale.com/admin/settings/trust-credentials))
   - Scope: **Devices: Write**
   - Tag: `tag:ci`
2. A `tag:ci` entry in your Tailscale ACL `tagOwners`
3. An ACL rule allowing `tag:ci` to reach your Coolify host on port 8000

GitHub secrets needed:

| Secret | Source |
|--------|--------|
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client |
| `TS_OAUTH_SECRET` | Tailscale OAuth client |
| `COOLIFY_API_TOKEN` | Coolify API token |
| `COOLIFY_SERVICE_UUID` | UUID returned when creating the service |

The CI runner joins the tailnet as an ephemeral node, calls the Coolify deploy API at the Tailscale IP, then disappears.

## Customizing the OpenClaw config

The BirdClaw image includes a seed `openclaw.json` at `birdclaw/openclaw.json`. On first boot, the entrypoint copies it to the config volume. After that, the volume-mounted config takes precedence and the seed is ignored.

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
- `gateway.controlUi.allowedOrigins` -- add your domain here if accessing the Control UI through a reverse proxy

Sensitive values (API keys, tokens) should be passed as environment variables, not baked into the config. OpenClaw reads `DISCORD_BOT_TOKEN`, `OPENCLAW_GATEWAY_TOKEN`, `ELEVENLABS_API_KEY`, etc. from the environment automatically.

## Host Node Setup (optional)

An OpenClaw "node" lets BirdClaw agents execute commands on the Docker host (diagnostics, Docker management, Tailscale, etc.), gated by an exec-approval allowlist. The node connects to the gateway through Traefik with TLS -- no ports are exposed on the host.

### Prerequisites

Node.js must be installed on the host (the openclaw CLI requires it):

```bash
# Arch/CachyOS
sudo pacman -S nodejs

# Ubuntu/Debian
sudo apt install nodejs
```

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
- **Coolify `SERVICE_FQDN_*` vs `SERVICE_URL_*`**: `SERVICE_FQDN_*` variables do NOT include the `https://` protocol prefix. Use `SERVICE_URL_*` when your app needs a full URL (e.g. BetterAuth requires `https://...`).
- **Coolify env var API**: `POST` to create, `PATCH` to update. Both use the **collection** endpoint `/api/v1/services/{uuid}/envs` with `{"key":"...","value":"..."}`. Do NOT PATCH individual env var UUID paths. Values are plaintext; Coolify encrypts internally. Never write directly to the Coolify database -- it will corrupt encrypted values.
- **Control UI pairing**: The "pairing required" screen is normal on first connect. It's a device trust handshake, not a login. Approve from inside the container with `openclaw devices approve --latest`, then log in with `AUTH_USERNAME`/`AUTH_PASSWORD`. Each new browser needs separate pairing approval.
- **Agent sandbox**: Requires Docker inside the container. The upstream OpenClaw image doesn't include Docker, so `sandbox.mode` should be `"off"` unless you add Docker-in-Docker to the Dockerfile.
- **qmd package name**: The npm package is `@tobilu/qmd`, not bare `qmd`. The binary is symlinked to `/usr/local/bin/qmd` in the Dockerfile since `bun install -g` puts binaries under `/root` which isn't on the `node` user's PATH.
- **Browser CDP port**: The `coollabsio/openclaw-browser` image exposes CDP on port 9222. The `BROWSER_CDP_URL` in the compose uses the service name `birdclaw_browser`.
- **Config corruption risk**: Never pipe `docker exec ... cat config.json | python3 ... | docker exec ... tee config.json` -- if the python step fails, `tee` truncates the file to zero bytes. Always copy out, modify locally, then `docker cp` back in.
- **Docker image caching**: GitHub Actions' GHA build cache may serve stale layers even after changing a Dockerfile instruction. If a fix isn't taking effect, change the instruction text (add a comment) to bust the cache.

## Volumes

| Volume | Mount | Contains | Backup priority |
|--------|-------|----------|----------------|
| `birdclaw-config` | `/home/node/.openclaw` | openclaw.json, credentials, paired devices, sessions | High |
| `birdclaw-workspace` | `/home/node/.openclaw/workspace` | Agent persona (SOUL.md, IDENTITY.md, etc.), memory, skills | Medium |
| `birdclaw-extensions` | `/home/node/.openclaw/extensions` | Installed plugins | Low (re-installable) |
| `birdclaw-browser-data` | `/config` | Chromium profile | Low |
| `birdclip-data` | `/paperclip` | Paperclip config, encryption keys | High |
| `birdclip-pgdata` | `/var/lib/postgresql/data` | Paperclip database | High |

Recommended backup: daily cron `tar` of the High/Medium priority volumes. The workspace contains BirdClaw's evolving "brain" files (SOUL.md, AGENTS.md, memory, etc.) which are not in this repo -- they live only in the volume.
