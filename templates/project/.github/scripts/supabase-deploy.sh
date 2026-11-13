#!/usr/bin/env bash
# Deploys a project's Supabase components, before the frontend (factory
# docs/architecture.md, "Components"), to the production project for
# production-deploy or to the shared staging project for preview-deploy (both
# main's definitions). Runs from main's checkout; the components come from its
# .factory/config.yaml, next to this script's .github/. The working directory is
# the checkout whose supabase/ is deployed: main's commit for production, the PR's
# head for a preview. Each step runs only for the kinds on host supabase:
#
#   1. the build points at no other project: any Supabase address in <artifact>
#      is VITE_SUPABASE_URL (all)
#   2. every function secret the code reads by literal name is set (api)
#   3. production: the migrations, without Vault values or seed data;
#      preview: staging reset to the PR's migrations and seed, against a minimal
#      config.toml written here, so nothing of the PR's config.toml reaches it (database)
#   4. every local migration is in the remote history, checked apart from
#      db push, which supabase/config.toml can switch off (database)
#   5. the functions, deleting the ones the deployed commit no longer has (api)
#
#   supabase-deploy.sh production|preview <artifact>
#
# Env: VITE_SUPABASE_URL (https://<ref>.supabase.co, from the repository variable
# VITE_SUPABASE_URL or STAGING_SUPABASE_URL: the project reference is read from
# it), SUPABASE_YES=1, SUPABASE_NO_KEYRING=1. The token is not in the environment: the CLI reads it from
# ~/.supabase/access-token, which the workflow writes. config.toml resolves
# env(VAR) from this environment, and a function's static_files would carry a
# token found there to Supabase. No database password: the CLI logs in through
# the token (factory docs/setup.md). Exits non-zero on the first failure; nothing
# after it runs.
set -euo pipefail

mode="${1:?production or preview}" art="${2:?artifact directory}"
dir="$(cd "$(dirname "$0")" && pwd)"
die() { echo "::error::supabase-deploy: $*"; exit 1; }
case "$mode" in
  production) var=VITE_SUPABASE_URL ;;
  preview) var=STAGING_SUPABASE_URL ;;
  *) die "mode $mode, not production or preview" ;;
esac
[ -z "${SUPABASE_ACCESS_TOKEN:-}" ] || die "SUPABASE_ACCESS_TOKEN is in the environment: config.toml could read it"

kinds="$(bash "$dir/components.sh" list | awk '$3 == "supabase" { print $2 }')"
has() { grep -qx "$1" <<<"$kinds"; }
[ -n "$kinds" ] || { echo "no Supabase components"; exit 0; }
[ -s "${SUPABASE_HOME:-$HOME/.supabase}/access-token" ] \
  || die "no token file: SUPABASE_ACCESS_TOKEN is missing from environment $mode (factory docs/setup.md)"

[[ "${VITE_SUPABASE_URL:-}" =~ ^https://([a-z]{20})\.supabase\.co$ ]] \
  || die "repository variable $var is '${VITE_SUPABASE_URL:-}', not https://<project ref>.supabase.co"
ref="${BASH_REMATCH[1]}"
here="$(pwd)"
# --agent no: plain output whatever the CLI detects about its caller. --workdir (below):
# exactly that directory's supabase/, with no search in parent directories.
sb() { supabase --agent no "$@"; }

# 1. What is deployed, not what the variable says: a literal or a build setting
# could point the bundle elsewhere.
# -a: an address in a binary asset counts too. Literal addresses only.
hosts="$(grep -rahoE 'https://[a-z]{20}\.supabase\.co' "$art" | sort -u || true)"
# No address is fine until the frontend uses Supabase (components come before the
# first story); a build older than the variables looks the same, so it is a warning.
if [ -z "$hosts" ]; then
  echo "::warning::the build has no Supabase address. If the app uses Supabase, the build is older than the repository variable $var: re-run all jobs of its tests run"
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
  have="$(sb secrets list --workdir "$here" --remote="$ref" -o json | jq -r '.[].name' | sort -u)"
  missing="$(comm -23 <(printf '%s\n' "$needed" | sed '/^$/d') <(printf '%s\n' "$have"))"
  [ -z "$missing" ] || die "function secrets not set: $(tr '\n' ' ' <<<"$missing")(supabase secrets set, then re-run this job)"
  echo "function secrets set: $(tr '\n' ' ' <<<"${needed:-none}")"
fi

if has database; then
  if [ "$mode" = production ]; then
    # 3. --skip-vault: Vault values from supabase/config.toml, the implementer's file,
    # never reach production; the owner sets them.
    sb db push --workdir "$here" --remote="$ref" --skip-vault
  else
    # A PR behind main: the build has main's changes, staging gets only the PR's.
    behind="$(comm -23 <(ls "$dir/../../supabase/migrations" 2>/dev/null | sort) <(ls supabase/migrations 2>/dev/null | sort))"
    [ -z "$behind" ] || echo "::warning::main has migrations this PR lacks ($(tr '\n' ' ' <<<"$behind")): merge main for an accurate preview"
    # 3. Staging takes the PR's migrations and seed only. The CLI's defaults run the
    # migrations and seed ./seed.sql; no Vault, no env() from the PR's config.toml.
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/supabase/migrations"
    printf 'project_id = "staging"\n' > "$tmp/supabase/config.toml"
    find supabase/migrations -maxdepth 1 -type f -name '*.sql' -exec cp {} "$tmp/supabase/migrations/" \; 2>/dev/null || true
    [ ! -f supabase/seed.sql ] || cp supabase/seed.sql "$tmp/supabase/seed.sql"
    sb db reset --workdir "$tmp" --remote="$ref"
  fi
  # 4. Every local migration (the file names db push applies) must be applied remotely.
  local_versions="$(find supabase/migrations -maxdepth 1 -type f -name '*.sql' 2>/dev/null \
    | sed -nE 's|^supabase/migrations/([0-9]+)_[^/]*\.sql$|\1|p' | sort -u || true)"
  remote_versions="$(sb migration list --workdir "$here" --remote="$ref" --output-format json \
    | jq -r '[.. | objects | select(has("migrations")) | .migrations] | first // [] | .[].remote | select(. != "")' | sort -u)"
  pending="$(comm -23 <(printf '%s\n' "$local_versions" | sed '/^$/d') <(printf '%s\n' "$remote_versions"))"
  [ -z "$pending" ] || die "migrations not applied on $mode: $(tr '\n' ' ' <<<"$pending")"
  echo "all $(grep -c . <<<"$local_versions" || true) migrations applied"
fi

# 5. --prune: the deployed commit is the truth, so a function removed from it stops
# being callable (in staging: also another PR's functions).
# The CLI refuses to deploy (or prune) with no function at all: the remote ones then stay.
if has api; then
  if compgen -G 'supabase/functions/*/index.*' >/dev/null; then
    sb functions deploy --workdir "$here" --remote="$ref" --use-api --prune
  else
    echo "::warning::no functions in supabase/functions: none deployed, and the project's existing functions stay (delete them by hand, factory docs/setup.md)"
  fi
fi
