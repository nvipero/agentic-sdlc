# Agent sandbox for a factory project.
# Policy (managed settings, firewall, allowlist) is baked into the image so that
# nothing inside the container can change it. scripts/up.sh rebuilds the image
# whenever .devcontainer/ changes on main.

# Node 24 (Maintenance LTS until 2028-04-30), pinned by digest.
FROM node:24-trixie-slim@sha256:43b9ba1142b8dcf33fa8f922ca1be85714adc444e0586c7cf7726daaeabc1bea

ARG CLAUDE_CODE_VERSION=2.1.308-1
# Fingerprint published at https://code.claude.com/docs/en/setup
ARG CLAUDE_CODE_SIGNER_FINGERPRINT=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg git jq less procps sudo \
      iptables ipset iproute2 dnsutils aggregate \
 && rm -rf /var/lib/apt/lists/*

# GitHub CLI from GitHub's signed apt repository.
RUN install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Claude Code from Anthropic's signed apt repository: root-owned, pinned, held.
RUN curl -fsSL https://downloads.claude.ai/keys/claude-code.asc -o /etc/apt/keyrings/claude-code.asc \
 && fpr="$(gpg --show-keys --with-colons /etc/apt/keyrings/claude-code.asc | awk -F: '/^fpr/{print $10; exit}')" \
 && { [ "$fpr" = "$CLAUDE_CODE_SIGNER_FINGERPRINT" ] || { echo "Claude Code signing fingerprint mismatch: $fpr" >&2; exit 1; }; } \
 && echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" \
      > /etc/apt/sources.list.d/claude-code.list \
 && apt-get update && apt-get install -y --no-install-recommends "claude-code=${CLAUDE_CODE_VERSION}" \
 && apt-mark hold claude-code \
 && rm -rf /var/lib/apt/lists/*

# Policy files: root-owned, read-only for the node user. The directories are
# created first: COPY --chmod would otherwise give them mode 0644 as well,
# and Claude Code would skip unreadable managed settings.
RUN install -d -m 0755 /etc/claude-code /etc/factory
COPY --chmod=0644 managed-settings.json /etc/claude-code/managed-settings.json
COPY --chmod=0644 allowlist.txt /etc/factory/allowlist.txt
COPY --chmod=0755 init-firewall.sh init-workspace.sh /usr/local/bin/
RUN echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall \
 && chmod 0440 /etc/sudoers.d/node-firewall \
 && visudo -cf /etc/sudoers.d/node-firewall

# Mount targets owned by node, so empty named volumes inherit that ownership.
RUN install -d -o node -g node /workspace /home/node/.claude

ENV DEVCONTAINER=true \
    CLAUDE_CONFIG_DIR=/home/node/.claude

USER node
WORKDIR /workspace

# Last, so it does not invalidate the layer cache: identifies which
# .devcontainer/ tree this image was built from (checked by scripts/up.sh).
ARG DEVCONTAINER_TREE=unset
LABEL factory.devcontainer.tree=$DEVCONTAINER_TREE
