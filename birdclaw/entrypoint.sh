#!/bin/sh
set -e

CONFIG_DIR="/home/node/.openclaw"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"
SEED_FILE="/home/node/.openclaw.seed/openclaw.json"

# Seed config on first run, substituting env vars for placeholders
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "[birdclaw] First run — seeding openclaw.json from image defaults"
  sed \
    -e "s|__OPENCLAW_AUTH_EMAIL__|${OPENCLAW_AUTH_EMAIL}|g" \
    -e "s|__DISCORD_OWNER_ID__|${DISCORD_OWNER_ID}|g" \
    -e "s|__DISCORD_GUILD_ID__|${DISCORD_GUILD_ID}|g" \
    -e "s|__ELEVENLABS_VOICE_ID__|${ELEVENLABS_VOICE_ID}|g" \
    "${SEED_FILE}" > "${CONFIG_FILE}"
fi

# Ensure qmd memory collection exists (survives restarts)
if command -v qmd >/dev/null 2>&1; then
  WORKSPACE="${CONFIG_DIR}/workspace"
  if [ -d "${WORKSPACE}" ] && ! qmd status 2>/dev/null | grep -q "memory-root-main"; then
    echo "[birdclaw] Initializing qmd memory collection"
    qmd collection add "${WORKSPACE}" --name memory-root-main 2>/dev/null || true
    qmd embed 2>/dev/null || true
  fi
fi

# Chain to the upstream Node docker-entrypoint.sh
exec docker-entrypoint.sh "$@"
