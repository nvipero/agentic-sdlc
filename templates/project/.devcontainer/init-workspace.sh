#!/bin/bash
# Prepares the workspace volume on every start. It never deletes anything:
# - an empty volume (only the read-only overlay mountpoints) is cloned into;
# - a complete clone (a .git whose HEAD resolves) is used as it is;
# - anything else stops the start with a description of what was found.
#   Resetting is explicit: scripts/up.sh reset-workspace on the host.
# Factory definition paths are excluded with sparse checkout: they are overlaid
# read-only from the host clone, and scripts/up.sh is not present at all.
set -euo pipefail

OVERLAYS='.factory .claude .github .devcontainer CLAUDE.md'

log() { echo "init-workspace: $*" >&2; }
stop() {
  log "STOPPING: $1"
  log "Nothing was changed. To archive this workspace and clone a fresh one, run on the host:"
  log "  scripts/up.sh reset-workspace"
  exit 1
}

# The entrypoint starts the firewall; wait for it (it can take a few seconds).
for _ in $(seq 1 60); do
  [ -f /run/firewall-ok ] && break
  sleep 1
done
[ -f /run/firewall-ok ] || { log "firewall is not active"; exit 1; }
[ -s /etc/factory/token/token ] || { log "no GitHub token at /etc/factory/token (start with scripts/up.sh)"; exit 1; }

# git gets github.com credentials from the gh wrapper (system config in the image).
# Commits carry the App's bot address, so GitHub shows them as the App; roles set
# their own name per commit (factory <role>).
bot="$(gh api graphql -f query='{viewer{login databaseId}}' --jq '.data.viewer | "\(.databaseId) \(.login)"')" \
  || { log "cannot read the App identity"; exit 1; }
git config --global user.name "${bot#* }"
git config --global user.email "${bot%% *}+${bot#* }@users.noreply.github.com"

cd /workspace

# Top-level entries other than the overlay mountpoints.
other_entries() {
  local e skip o
  for e in .[!.]* ..?* *; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    skip=
    for o in $OVERLAYS; do [ "$e" = "$o" ] && skip=1; done
    [ -n "$skip" ] || echo "$e"
  done
}

if [ ! -e .git ]; then
  others="$(other_entries)"
  [ -z "$others" ] || stop "the workspace has files but no .git: $(echo $others)"
  : "${FACTORY_REPO_URL:?FACTORY_REPO_URL is not set}"
  log "empty workspace: cloning $FACTORY_REPO_URL"
  git init -q -b main
  git config sparse.expectFilesOutsideOfPatterns true
  git remote add origin "$FACTORY_REPO_URL"
  git sparse-checkout set --no-cone \
    '/*' '!/.factory/' '!/.claude/' '!/.github/' '!/.devcontainer/' '!/CLAUDE.md' '!/scripts/up.sh'
  git fetch -q origin main
  git checkout -q -B main --track origin/main
elif ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  head_ref="$(git symbolic-ref -q HEAD 2>/dev/null || echo 'unreadable')"
  branches="$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | tr '\n' ' ')"
  stop "HEAD does not resolve (HEAD -> ${head_ref}; local branches: ${branches:-none}). This can be an orphan branch with no commits, an interrupted clone, or a damaged repository."
fi

# The overlays follow the owner's main, which can be ahead of this clone. New
# files there would show as untracked and could be staged by `git add -A`.
# Missing entries are added on every start; other entries are kept.
for p in /.factory/ /.claude/ /.github/ /.devcontainer/ /CLAUDE.md; do
  grep -qxF "$p" .git/info/exclude 2>/dev/null || echo "$p" >> .git/info/exclude
done
log "OK: $(git rev-parse --abbrev-ref HEAD) at $(git rev-parse --short HEAD)"
