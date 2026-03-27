#!/bin/sh
set -e

CONFIG_DIR="/home/node/.openclaw"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"
SEED_FILE="/home/node/.openclaw.seed/openclaw.json"

# Seed config on first run
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "[birdclaw] First run — seeding openclaw.json from image defaults"
  cp "${SEED_FILE}" "${CONFIG_FILE}"
fi

# Chain to the upstream Node docker-entrypoint.sh
exec docker-entrypoint.sh "$@"
