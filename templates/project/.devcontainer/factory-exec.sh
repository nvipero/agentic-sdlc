#!/bin/bash
# Every exec from scripts/up.sh goes through this guard: it refuses to run the
# command unless the firewall marker exists (on tmpfs, so it never survives a
# restart) and the network behaves as the allowlist says.
set -euo pipefail

refuse() { echo "factory-exec: REFUSING: $*" >&2; exit 1; }

[ -f /run/firewall-ok ] || refuse "firewall marker missing"
[ "$(stat -f -c %T /run)" = "tmpfs" ] || refuse "/run is not tmpfs"
jq -e .permissions.deny /etc/claude-code/managed-settings.json >/dev/null \
  || refuse "managed settings not readable"
if curl -s --max-time 5 -o /dev/null https://example.com; then
  refuse "example.com is reachable"
fi
curl -fsS --max-time 10 -o /dev/null https://api.github.com/zen || refuse "api.github.com unreachable"

[ "$#" -gt 0 ] || set -- bash -l
exec "$@"
