#!/bin/bash
# Clones the project into the workspace volume on first start. Factory
# definition paths are excluded with sparse checkout: they are overlaid
# read-only from the host clone, and scripts/up.sh is not present at all.
set -euo pipefail

log() { echo "init-workspace: $*" >&2; }

[ -f /run/firewall-ok ] || { log "firewall is not active"; exit 1; }
[ -n "${GH_TOKEN:-}" ] || { log "GH_TOKEN is not set (start with scripts/up.sh)"; exit 1; }

gh auth setup-git --hostname github.com
git config --global user.name "factory-agent"
git config --global user.email "factory-agent@users.noreply.github.com"

cd /workspace
if [ ! -d .git ]; then
  : "${FACTORY_REPO_URL:?FACTORY_REPO_URL is not set}"
  log "cloning $FACTORY_REPO_URL"
  git init -q -b main
  git config sparse.expectFilesOutsideOfPatterns true
  git remote add origin "$FACTORY_REPO_URL"
  git sparse-checkout set --no-cone \
    '/*' '!/.factory/' '!/.claude/' '!/.github/' '!/.devcontainer/' '!/CLAUDE.md' '!/scripts/up.sh'
  git fetch -q origin main
  git checkout -q -B main --track origin/main
fi
log "OK: $(git rev-parse --abbrev-ref HEAD) at $(git rev-parse --short HEAD)"
