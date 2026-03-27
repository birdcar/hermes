FROM ghcr.io/openclaw/openclaw:latest

ARG EXTRA_APT_PACKAGES=""

USER root

# Install gh CLI + optional extras
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh jq ${EXTRA_APT_PACKAGES} \
    && rm -rf /var/lib/apt/lists/*

# Install bun globally
RUN curl -fsSL https://bun.sh/install | bash \
    && mv /root/.bun /usr/local/bun
ENV PATH="/usr/local/bun/bin:${PATH}"

# Install qmd CLI (QMD memory backend — @tobilu/qmd on npm)
# Installs as root so the binary lands in a global path accessible to all users
RUN bun install -g @tobilu/qmd && \
    ln -sf $(find /root -name qmd -type f 2>/dev/null | head -1) /usr/local/bin/qmd

# Pre-create volume mount targets with correct ownership
RUN mkdir -p /home/node/.openclaw/extensions \
             /home/node/.openclaw/workspace \
             /home/node/.openclaw/media \
             /home/node/.openclaw/skills \
    && chown -R node:node /home/node/.openclaw

# Copy seed config (used on first run only)
COPY --chown=node:node openclaw.json /home/node/.openclaw.seed/openclaw.json

# Copy entrypoint wrapper
COPY --chown=node:node entrypoint.sh /usr/local/bin/birdclaw-entrypoint.sh
RUN chmod +x /usr/local/bin/birdclaw-entrypoint.sh

USER node
WORKDIR /app

EXPOSE 18789 18790

ENTRYPOINT ["/usr/local/bin/birdclaw-entrypoint.sh"]
CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured"]
