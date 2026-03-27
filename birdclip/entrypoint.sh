#!/bin/sh
set -e

# $HOME resolves to /paperclip (the data volume), so these flags persist across restarts
CLAUDE_JSON="$HOME/.claude.json"
PAPERCLIP_CONFIG="${PAPERCLIP_CONFIG:-/paperclip/instances/default/config.json}"

# 1. Pre-seed Claude Code onboarding flag (prevents interactive wizard)
if [ ! -f "$CLAUDE_JSON" ]; then
  echo '{"hasCompletedOnboarding":true}' > "$CLAUDE_JSON"
fi

# 2. Run Paperclip onboard if no config exists yet (first boot)
if [ ! -f "$PAPERCLIP_CONFIG" ]; then
  echo "First run detected — running onboard..."
  npx paperclipai onboard --yes
  echo "Onboard complete. Run 'docker exec <container> npx paperclipai auth bootstrap-ceo' to create admin invite."
fi

# 3. Hand off to the original CMD
exec "$@"
