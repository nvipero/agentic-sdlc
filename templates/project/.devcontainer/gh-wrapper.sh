#!/bin/bash
# gh for the agents: reads the GitHub App token from the read-only token mount
# on every call, so a token refreshed on the host is used at once. The token is
# put only in the real gh's environment, never in its arguments. git uses this
# too, as its credential helper for github.com (see the Dockerfile).
set -euo pipefail
f=/etc/factory/token/token
[ -s "$f" ] || { echo "gh: no GitHub token at $f (start the container with scripts/up.sh)" >&2; exit 1; }
GH_TOKEN="$(cat "$f")" exec /usr/bin/gh "$@"
