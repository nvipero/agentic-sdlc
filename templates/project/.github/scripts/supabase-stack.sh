#!/usr/bin/env bash
# The Supabase local stack for the acceptance tests of a project with Supabase
# components (factory docs/architecture.md, "Components"). Starts it from the
# committed supabase/supabase.lock (stopping a running one first), resets the database to
# the branch's migrations and seed, and prints the values the app and the tests
# read, one NAME=value per line: API_URL as VITE_SUPABASE_URL, ANON_KEY as
# VITE_SUPABASE_ANON_KEY, PUBLISHABLE_KEY as VITE_SUPABASE_PUBLISHABLE_KEY, the
# rest under the CLI's names. They are the local stack's published demo values,
# not credentials. Ports change per stack, so nothing may use a literal address.
#
#   supabase-stack.sh native   in the container (/factory:run, the roles)
#   supabase-stack.sh docker   in the tests workflow
#
# Prints nothing and exits non-zero, with the CLI's last lines on stderr, when
# the stack does not start: a broken environment, never a test result.
set -euo pipefail

runtime="${1:?runtime: native or docker}"
case "$runtime" in native | docker) ;; *) echo "supabase-stack: runtime $runtime, not native or docker" >&2; exit 2 ;; esac
[ -f supabase/supabase.lock ] || { echo "supabase-stack: no supabase/supabase.lock (factory docs/setup.md)" >&2; exit 1; }

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
run() { "$@" >"$log" 2>&1 || { echo "supabase-stack: $* failed:" >&2; tail -20 "$log" >&2; exit 1; }; }

# A running stack keeps the supabase/config.toml it started with: stop it first,
# so every run uses the branch's. Nothing to stop is fine.
supabase stop >/dev/null 2>&1 || true
# Studio, pgmeta, analytics and the pooler are not in the image (.devcontainer/Dockerfile).
# --eager: every service runs before the tests start, and none stops when idle.
run supabase start --runtime "$runtime" --frozen --eager -x studio,analytics,pooler
run supabase db reset
status="$(supabase status --env --override-name API_URL=VITE_SUPABASE_URL,ANON_KEY=VITE_SUPABASE_ANON_KEY,PUBLISHABLE_KEY=VITE_SUPABASE_PUBLISHABLE_KEY 2>"$log")" \
  || { echo "supabase-stack: supabase status failed:" >&2; tail -20 "$log" >&2; exit 1; }
# Unquoted and checked, so the lines work both with export and in $GITHUB_ENV.
vars="$(sed -E "s/^([A-Z0-9_]+)='(.*)'$/\1=\2/" <<<"$status")"
bad="$(grep -vE '^[A-Z0-9_]+=[A-Za-z0-9._:/@-]*$' <<<"$vars" || true)"
[ -z "$bad" ] || { echo "supabase-stack: unexpected status line: $(head -1 <<<"$bad")" >&2; exit 1; }
grep -q '^VITE_SUPABASE_URL=http' <<<"$vars" || { echo "supabase-stack: no API_URL in the stack's status" >&2; exit 1; }
echo "$vars"
