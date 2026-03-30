# CI/CD

## Overview

The GitHub Actions workflow (`.github/workflows/build-images.yml`) builds both images and pushes them to GHCR, then triggers a Coolify redeploy via the API.

Triggers: push to `main`, weekly on Mondays at 6am UTC, manual dispatch.

## Image publishing

Both images publish to:
- `ghcr.io/birdcar/hermes/birdclaw:latest`
- `ghcr.io/birdcar/hermes/birdclaw:YYYY.MM.DD`
- `ghcr.io/birdcar/hermes/birdclip:latest`
- `ghcr.io/birdcar/hermes/birdclip:YYYY.MM.DD`

The workflow uses GHA layer caching. If a Dockerfile change isn't taking effect after a push, the cache may be serving stale layers — add or modify a comment in the relevant Dockerfile instruction to force a cache bust.

**GHCR package visibility is separate from repo visibility.** Making the GitHub repo public does not make existing packages public. Each package must be set to public individually at `github.com/users/birdcar/packages/container/PACKAGE/settings`.

## Auto-deploy via Tailscale

After both images build successfully, the `deploy` job connects to your Tailscale network and calls the Coolify deploy API at the host's Tailscale IP. The CI runner joins as an ephemeral node and disappears after the job finishes.

### Setup

1. Create a Tailscale OAuth client at [Tailscale Admin > Settings > Trust credentials](https://login.tailscale.com/admin/settings/trust-credentials)
   - Scope: **Devices: Write**
   - Tag: `tag:ci`

2. Add `tag:ci` to your Tailscale ACL `tagOwners`:
   ```json
   "tagOwners": {
     "tag:ci": ["autogroup:admin"]
   }
   ```

3. Add an ACL rule allowing `tag:ci` to reach your Coolify host on port 8000:
   ```json
   {"action": "accept", "src": ["tag:ci"], "dst": ["YOUR_COOLIFY_HOST:8000"]}
   ```

4. Add these GitHub Actions secrets to the repository:

| Secret | Source |
|--------|--------|
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client |
| `TS_OAUTH_SECRET` | Tailscale OAuth client |
| `COOLIFY_API_TOKEN` | Coolify dashboard API token |
| `COOLIFY_SERVICE_UUID` | UUID returned when creating the Hermes service |

The deploy job calls `POST /api/v1/deploy?uuid=SERVICE_UUID` on the Coolify host's Tailscale IP (currently hardcoded in the workflow as `100.108.157.126:8000`). Update this if your Coolify host's Tailscale IP changes.
