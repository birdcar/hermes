# Host Node Setup

An OpenClaw "node" lets BirdClaw agents execute commands on the Docker host — diagnostics, Docker management, Tailscale, service checks, etc. — gated by an exec-approval allowlist. The node connects to the BirdClaw gateway through Traefik over TLS. No extra ports are opened on the host.

This is optional. BirdClaw works without it.

## Prerequisites

Node.js and bun must be installed on the host (the `openclaw` CLI requires both):

```bash
# Arch/CachyOS
sudo pacman -S nodejs

# Ubuntu/Debian
sudo apt install nodejs

# Install bun
curl -fsSL https://bun.sh/install | bash
```

## Install

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

# Install the systemd user service
mkdir -p ~/.config/systemd/user ~/.config/environment.d
cp host/birdclaw-node.service ~/.config/systemd/user/
echo 'OPENCLAW_GATEWAY_TOKEN=YOUR_TOKEN' > ~/.config/environment.d/birdclaw.conf
systemctl --user daemon-reload
systemctl --user enable --now birdclaw-node.service
```

## Pair the node

After the service starts, approve the pending pairing request from inside the BirdClaw container:

```bash
docker exec -it BIRDCLAW_CONTAINER openclaw devices approve --latest
```

## Exec approval policy

`host/exec-approvals.json` controls what the node will run automatically vs. prompt for:

| Setting | Value | Effect |
|---------|-------|--------|
| `security` | `allowlist` | Only allowlisted patterns auto-execute |
| `ask` | `on-miss` | Commands not in the allowlist prompt for approval |
| `askFallback` | `deny` | If approval UI unavailable, block the command |

The default allowlist covers read-only diagnostics: `docker *`, `df`, `free`, `ps aux`, `journalctl`, `systemctl status`, `tailscale status/ping`, and `/usr/local/bin/homelab-curl`. Raw `curl` is intentionally excluded — agents use `homelab-curl` which validates target domains against `allowed-domains.json` before making requests.

"Always allow" choices grow the allowlist over time. Edit `~/.openclaw/exec-approvals.json` directly to add or remove patterns.

## homelab-curl

`host/homelab-curl` is a wrapper around `curl` that checks the target domain against `~/.config/homelab-curl/allowed-domains.json` before executing. The default allowlist restricts requests to `*.birdcar.dev`. Update `allowed-domains.json` to add domains your setup needs to reach.
