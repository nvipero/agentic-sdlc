#!/usr/bin/env bash
# Deploys a project's Supabase components to its production project, for
# production-deploy (environment "production", main's definition), before the
# frontend (factory docs/architecture.md, "Components"). Runs at the root of a
# checkout of the deployed commit; reads the components from its
# .factory/config.yaml. Each step runs only for the kinds on host supabase:
#
#   1. the build points at no other project: any Supabase address in <artifact>
#      is VITE_SUPABASE_URL (all)
#   2. every function secret the code reads by literal name is set (api)
#   3. the migrations, without Vault values or seed data (database)
#   4. every local migration is in the remote history, checked apart from
#      db push, which supabase/config.toml can switch off (database)
#   5. the functions, deleting the ones main no longer has (api)
#
#   supabase-deploy.sh <artifact>
#
# Env: SUPABASE_ACCESS_TOKEN (scoped to the project), VITE_SUPABASE_URL (the
# repository variable, https://<ref>.supabase.co: the project reference is read
# from it), SUPABASE_YES=1. No database password: db push logs in through the
# token (factory docs/setup.md). Exits non-zero on the first failure; nothing
# after it runs.
set -euo pipefail

art="${1:?artifact directory}"
dir="$(cd "$(dirname "$0")" && pwd)"
die() { echo "::error::supabase-deploy: $*"; exit 1; }

kinds="$(bash "$dir/components.sh" list | awk '$3 == "supabase" { print $2 }')"
has() { grep -qx "$1" <<<"$kinds"; }
[ -n "$kinds" ] || { echo "no Supabase components"; exit 0; }

[[ "${VITE_SUPABASE_URL:-}" =~ ^https://([a-z]{20})\.supabase\.co$ ]] \
  || die "repository variable VITE_SUPABASE_URL is '${VITE_SUPABASE_URL:-}', not https://<project ref>.supabase.co"
ref="${BASH_REMATCH[1]}"
# --agent no: plain output whatever the CLI detects about its caller.
sb() { supabase --agent no "$@"; }

# 1. What is deployed, not what the variable says: a literal or a build setting
# could point the bundle elsewhere.
# -a: an address in a binary asset counts too. Literal addresses only.
hosts="$(grep -rahoE 'https://[a-z]{20}\.supabase\.co' "$art" | sort -u || true)"
# No address is fine until the frontend uses Supabase (components come before the
# first story); a build older than the variables looks the same, so it is a warning.
if [ -z "$hosts" ]; then
  echo "::warning::the build has no Supabase address. If the app uses Supabase, main's build is older than the repository variables: re-run all jobs of main's tests run"
else
  [ "$hosts" = "$VITE_SUPABASE_URL" ] \
    || die "the build's Supabase addresses are '$(tr '\n' ' ' <<<"$hosts")', expected only $VITE_SUPABASE_URL"
  echo "the build points at $VITE_SUPABASE_URL"
fi

# 2. Literal names only, outside the Deno tests; Supabase sets SUPABASE_* itself.
# Values are never read or printed.
if has api; then
  needed="$(find supabase/functions -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.mjs' \) ! -name '*_test.*' ! -path 'supabase/functions/tests/*' -print0 2>/dev/null \
    | xargs -0 -r grep -hoE "Deno\.env\.get\( *[\"'][A-Za-z_][A-Za-z0-9_]*[\"'] *\)" \
    | sed -E "s/.*[\"']([A-Za-z0-9_]+)[\"'].*/\1/" | grep -v '^SUPABASE_' | sort -u || true)"
  have="$(sb secrets list --remote="$ref" -o json | jq -r '.[].name' | sort -u)"
  missing="$(comm -23 <(printf '%s\n' "$needed" | sed '/^$/d') <(printf '%s\n' "$have"))"
  [ -z "$missing" ] || die "function secrets not set: $(tr '\n' ' ' <<<"$missing")(supabase secrets set, then re-run this job)"
  echo "function secrets set: $(tr '\n' ' ' <<<"${needed:-none}")"
fi

if has database; then
  # 3. --skip-vault: Vault values from supabase/config.toml, the implementer's file,
  # never reach production; the owner sets them.
  sb db push --remote="$ref" --skip-vault
  # 4. Every local migration (the file names db push applies) must be applied remotely.
  local_versions="$(find supabase/migrations -maxdepth 1 -type f -name '*.sql' 2>/dev/null \
    | sed -nE 's|^supabase/migrations/([0-9]+)_[^/]*\.sql$|\1|p' | sort -u || true)"
  remote_versions="$(sb migration list --remote="$ref" --output-format json \
    | jq -r '[.. | objects | select(has("migrations")) | .migrations] | first // [] | .[].remote | select(. != "")' | sort -u)"
  pending="$(comm -23 <(printf '%s\n' "$local_versions" | sed '/^$/d') <(printf '%s\n' "$remote_versions"))"
  [ -z "$pending" ] || die "migrations not applied on production: $(tr '\n' ' ' <<<"$pending")"
  echo "all $(grep -c . <<<"$local_versions" || true) migrations applied"
fi

# 5. --prune: main is the truth, so a function removed from it stops being callable.
# The CLI refuses to deploy (or prune) with no function at all: the remote ones then stay.
if has api; then
  if compgen -G 'supabase/functions/*/index.*' >/dev/null; then
    sb functions deploy --remote="$ref" --use-api --prune
  else
    echo "::warning::no functions in supabase/functions: none deployed, and the project's existing functions stay (delete them by hand, factory docs/setup.md)"
  fi
fi
