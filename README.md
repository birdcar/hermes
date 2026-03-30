# Hermes

Custom Docker images and Coolify deployment config for two AI services: **BirdClaw** (custom [OpenClaw](https://openclaw.ai)) and **BirdClip** (custom [Paperclip](https://github.com/paperclipai/paperclip)).

## Services

```
birdclaw          OpenClaw gateway + bun/gh/qmd    :18789
birdclaw_browser  Chromium CDP sidecar             :9222
birdclip          Paperclip server + UI            :3100
birdclip_db       PostgreSQL 17                    :5432
```

All four share a Docker Compose network. Inter-service communication uses Docker DNS (`http://birdclaw:18789`, `http://birdclaw_browser:9222`, etc.). External access goes through Coolify's Traefik proxy.

## Images

| Image | Base | Extras |
|-------|------|--------|
| `ghcr.io/birdcar/hermes/birdclaw` | `ghcr.io/openclaw/openclaw:latest` | bun.js, gh CLI, qmd (`@tobilu/qmd`), pre-seeded config |
| `ghcr.io/birdcar/hermes/birdclip` | `node:lts-trixie-slim` | Paperclip built from source, claude-code CLI, gh CLI |

Images build on push to `main` and weekly (Mondays 6am UTC). After a successful build, CI joins your Tailscale network and triggers a Coolify redeploy. See [docs/ci-cd.md](docs/ci-cd.md) for setup.

## Prerequisites

- [Coolify](https://coolify.io) v4 with Traefik proxy
- Wildcard DNS pointing to your Coolify server
- A Claude Max subscription (for `CLAUDE_CODE_OAUTH_TOKEN`)
- [Tailscale](https://tailscale.com) (for CI auto-deploy)

## Deployment

### 1. Create the Coolify service

```bash
COMPOSE_B64=$(base64 -w 0 < docker-compose.yml)

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

Use `POST` to create a new variable, `PATCH` to update an existing one. Both go to the collection endpoint — not individual env var UUID paths.

```bash
# Create
curl -X POST "https://your-coolify.example.com/api/v1/services/SERVICE_UUID/envs" \
  -H "Authorization: Bearer YOUR_COOLIFY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "CLAUDE_CODE_OAUTH_TOKEN", "value": "sk-ant-oat01-..."}'

# Update
curl -X PATCH "https://your-coolify.example.com/api/v1/services/SERVICE_UUID/envs" \
  -H "Authorization: Bearer YOUR_COOLIFY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "CLAUDE_CODE_OAUTH_TOKEN", "value": "new-value"}'
```

Required variables:

| Variable | How to get it | Used by |
|----------|---------------|---------|
| `CLAUDE_CODE_OAUTH_TOKEN` | `claude setup-token` on a machine with Claude Max | birdclaw, birdclip |
| `OPENCLAW_GATEWAY_TOKEN` | `openssl rand -base64 48` | birdclaw |
| `OPENCLAW_HOOKS_TOKEN` | `openssl rand -hex 32` | birdclaw, birdclip |
| `AUTH_USERNAME` | Your choice | birdclaw (Control UI) |
| `AUTH_PASSWORD` | Your choice | birdclaw (Control UI) |
| `DISCORD_BOT_TOKEN` | Discord Developer Portal | birdclaw |
| `ELEVENLABS_API_KEY` | ElevenLabs dashboard | birdclaw |
| `BETTER_AUTH_SECRET` | `openssl rand -hex 32` | birdclip |

See `.env.example` for the full list including optional infrastructure API keys.

### 3. Configure domains

In the Coolify dashboard, set FQDNs for the two web-facing services and enable "Connect to Predefined Network" for Traefik routing.

| Service | Port |
|---------|------|
| `birdclaw` | 18789 |
| `birdclip` | 3100 |

### 4. Deploy

```bash
curl -X POST "https://your-coolify.example.com/api/v1/services/SERVICE_UUID/start" \
  -H "Authorization: Bearer YOUR_COOLIFY_API_TOKEN"
```

### 5. Pair the Control UI

On first visit to `https://birdclaw.your-domain.dev`, the Control UI shows "pairing required." This is the device trust handshake, not an error.

1. Enter the websocket URL and gateway token in the browser UI
2. Approve the pending pairing request from inside the container:
   ```bash
   docker exec -it BIRDCLAW_CONTAINER openclaw devices approve --latest
   ```
3. Log in with your `AUTH_USERNAME` / `AUTH_PASSWORD`

Each browser or device needs its own pairing approval.

### 6. Verify

```bash
curl -sf https://birdclaw.your-domain.dev/healthz
curl -sf https://paperclip.your-domain.dev/health
```

## Volumes

| Volume | Mount | Contains | Backup priority |
|--------|-------|----------|----------------|
| `birdclaw-config` | `/home/node/.openclaw` | openclaw.json, credentials, paired devices | High |
| `birdclaw-workspace` | `/home/node/.openclaw/workspace` | Agent persona files, memory, skills | High |
| `birdclaw-extensions` | `/home/node/.openclaw/extensions` | Installed plugins | Low |
| `birdclaw-qmd-cache` | `/home/node/.cache/qmd` | qmd embedding cache | Low |
| `birdclaw-gh-config` | `/home/node/.config/gh` | gh CLI credentials | Medium |
| `birdclaw-browser-data` | `/config` | Chromium profile | Low |
| `birdclip-data` | `/paperclip` | Paperclip config, encryption keys | High |
| `birdclip-gh-config` | `/paperclip/.config/gh` | gh CLI credentials | Medium |
| `birdclip-pgdata` | `/var/lib/postgresql/data` | Paperclip database | High |

The workspace volume contains BirdClaw's evolving persona and memory files (SOUL.md, AGENTS.md, qmd index, etc.) — these live only in the volume, not in this repo.

## Customizing the OpenClaw config

`birdclaw/openclaw.json` is the seed config. On first boot the entrypoint copies it to the config volume; after that the volume takes precedence.

To edit the live config:

```bash
docker exec -it BIRDCLAW_CONTAINER vi /home/node/.openclaw/openclaw.json
docker restart BIRDCLAW_CONTAINER
```

Key sections: `channels.discord`, `agents.defaults.model`, `messages.tts`, `memory`, `plugins.load.paths`, `gateway.controlUi.allowedOrigins`.

Pass secrets (API keys, tokens) as environment variables rather than baking them into the config. OpenClaw reads `DISCORD_BOT_TOKEN`, `OPENCLAW_GATEWAY_TOKEN`, `ELEVENLABS_API_KEY`, etc. from the environment automatically.

## Gotchas

**GHCR package visibility** — Making the repo public does not make existing packages public. Each package must be set to public individually at `github.com/users/YOU/packages/container/PACKAGE/settings`.

**Coolify `SERVICE_FQDN_*` vs `SERVICE_URL_*`** — `SERVICE_FQDN_*` variables do not include the `https://` scheme. Use `SERVICE_URL_*` when your app needs a full URL (BetterAuth requires `https://...`).

**Config file editing** — Never pipe `docker exec ... cat config.json | some-transform | docker exec ... tee config.json`. If the transform step fails, `tee` truncates the file to zero bytes. Copy out, modify locally, then `docker cp` back in.

**Docker build cache** — GitHub Actions' GHA cache can serve stale layers after a Dockerfile change. If a fix isn't taking effect, add a comment to bust the layer cache.

**Browser CDP port** — The `coollabsio/openclaw-browser` image exposes Chrome on port 9222. `BROWSER_CDP_URL` should be `http://birdclaw_browser:9222` (not 9223).

## Further reading

- [docs/architecture.md](docs/architecture.md) — image details, volume layout, network topology
- [docs/ci-cd.md](docs/ci-cd.md) — GitHub Actions setup, Tailscale CI requirements
- [docs/host-node.md](docs/host-node.md) — optional host node setup for agent shell access
