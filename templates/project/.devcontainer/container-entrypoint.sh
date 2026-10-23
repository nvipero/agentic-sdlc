#!/bin/bash
# Container entrypoint: the firewall comes up before anything else, on every
# start (including a manual docker restart). If it fails, this script exits
# non-zero and the container stops.
set -euo pipefail

if ! sudo /usr/local/bin/init-firewall.sh; then
  echo "container-entrypoint: firewall failed; stopping container" >&2
  exit 1
fi
exec "$@"
