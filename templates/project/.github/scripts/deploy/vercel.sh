#!/usr/bin/env bash
# Deployment target "vercel" (the frontend's host in .factory/config.yaml), for
# preview-deploy, preview-cleanup (environment "preview") and production-deploy
# (environment "production"), all main's definitions.
#
#   vercel.sh install                     the Vercel CLI; run without secrets
#   vercel.sh assemble <dir> <out>        the deployable output in <out>; run without secrets
#   vercel.sh preview <out> <pr>          deploy <out> as a preview of the PR; prints its URL
#   vercel.sh address <pr> <url>          give the PR its stable address; prints it
#   vercel.sh prune <pr> [<keep-url>]     delete the PR's other previews
#   vercel.sh production <out> <sha>      deploy <out> to production; prints its URL
#   vercel.sh live <url>                  fail unless production serves <url>; prints the address
#
# <dir> holds the checked build (regular files only, with index.html). Only its
# files are copied into a static-only Build Output: no functions, routes or
# project settings from the build. The frontend's spa in .factory/config.yaml is not
# supported here: assemble fails on it rather than ignoring it.
#
# Addresses: a PR's preview at <owner>-<repo>-pr-<n>.vercel.app, production at
# <repo>.vercel.app (the Vercel project is named after the repository). Vercel
# makes a project's first deployment production, so the project has a placeholder
# production deployment from setup, and previews always use --target=preview.
#
# Env: VERCEL_TOKEN, VERCEL_ORG_ID, VERCEL_PROJECT_ID; GITHUB_REPOSITORY. The
# token goes to curl in a config on stdin, never in its arguments. Only
# deployments that are previews (no target) and carry this PR's number as
# metadata are ever deleted, so the production placeholder cannot be touched.
set -euo pipefail

CLI=vercel@64.3.1

vapi() {   # vapi <method> <path> [json body]
  local sep='?' team=
  [[ "$2" == *\?* ]] && sep='&'
  [[ "$VERCEL_ORG_ID" == team_* ]] && team="teamId=$VERCEL_ORG_ID"
  printf 'header = "Authorization: Bearer %s"\n' "$VERCEL_TOKEN" \
    | curl -fsS --max-time 30 -K - -X "$1" -H 'Content-Type: application/json' \
        ${3:+--data "$3"} "https://api.vercel.com$2${team:+$sep$team}"
}

# Lowercase letters, digits and hyphens, as Vercel host names.
hostpart() { printf '%s' "$1" | tr '/A-Z' '-a-z' | tr -cd 'a-z0-9-'; }

# deploy <out> <vercel deploy options...>: prints the deployment URL.
deploy() {
  local dir="$1" log url; shift
  [ -f "$dir/.vercel/output/config.json" ] || { echo "nothing assembled in $dir" >&2; exit 1; }
  log="$(mktemp)"
  (cd "$dir" && vercel deploy --prebuilt "$@" --non-interactive --no-color) > "$log"
  # stdout carries the deployment URL; take the first one.
  url="$(grep -oE 'https://[a-z0-9-]+\.vercel\.app' "$log" | head -1 || true)"
  [ -n "$url" ] || { echo "no deployment URL in the output" >&2; cat "$log" >&2; exit 1; }
  echo "$url"
}

case "${1:-}" in
  install)
    npm install --global --ignore-scripts "$CLI"
    ;;
  assemble)
    dir="${2:-}" out="${3:-}"
    [ -f "$dir/index.html" ] || { echo "no index.html in '$dir'" >&2; exit 1; }
    [ -n "$out" ] || { echo "no output directory" >&2; exit 1; }
    spa="$(bash "$(dirname "$0")/../components.sh" frontend)"
    [ "${spa#* }" = false ] || { echo "spa is not supported on vercel" >&2; exit 1; }
    mkdir -p "$out/.vercel/output/static"
    printf '{"version":3}\n' > "$out/.vercel/output/config.json"
    cp -R "$dir"/. "$out/.vercel/output/static/"
    ;;
  preview)
    dir="${2:-}" pr="${3:-}"
    [[ "$pr" =~ ^[0-9]+$ ]] || { echo "bad PR number" >&2; exit 1; }
    deploy "$dir" --target=preview --meta "pr=$pr"
    ;;
  address)
    pr="${2:-}" url="${3:-}"; url="${url#https://}"
    [[ "$pr" =~ ^[0-9]+$ ]] || { echo "bad PR number" >&2; exit 1; }
    repo="$(hostpart "${GITHUB_REPOSITORY:-}")"; [ -n "$repo" ] || { echo "no GITHUB_REPOSITORY" >&2; exit 1; }
    host="$repo-pr-$pr.vercel.app"
    [[ "$url" =~ ^[a-z0-9-]+\.vercel\.app$ && "$host" =~ ^[a-z0-9-]+\.vercel\.app$ ]] || { echo "bad host" >&2; exit 1; }
    vapi POST "/v2/deployments/$url/aliases" "{\"alias\":\"$host\"}" | jq -r '"alias \(.alias) set"' >&2
    echo "https://$host"
    ;;
  prune)
    pr="${2:-}" keep="${3:-}"; keep="${keep#https://}"
    [[ "$pr" =~ ^[0-9]+$ ]] || { echo "bad PR number" >&2; exit 1; }
    vapi GET "/v7/deployments?projectId=$VERCEL_PROJECT_ID&limit=100" \
      | jq -r --arg pr "$pr" --arg keep "$keep" \
          '.deployments[] | select(.target == null and (.meta.pr // "") == $pr and .url != $keep) | .uid' \
      | while read -r uid; do
          [[ "$uid" =~ ^dpl_[A-Za-z0-9]+$ ]] || continue
          vapi DELETE "/v13/deployments/$uid" | jq -r '"\(.uid) \(.state)"'
        done
    ;;
  production)
    dir="${2:-}" sha="${3:-}"
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "bad commit" >&2; exit 1; }
    deploy "$dir" --prod --meta "sha=$sha"
    ;;
  live)
    # The production domain moves to a new production deployment on its own, except
    # after an Instant Rollback in the dashboard, which turns that off until undone.
    url="${2:-}"; url="${url#https://}"; repo="${GITHUB_REPOSITORY:-}"
    host="$(hostpart "${repo#*/}").vercel.app"
    [[ "$url" =~ ^[a-z0-9-]+\.vercel\.app$ && "$host" =~ ^[a-z0-9-]+\.vercel\.app$ ]] || { echo "bad host" >&2; exit 1; }
    id="$(vapi GET "/v13/deployments/$url" | jq -r .id)"
    [[ "$id" =~ ^dpl_[A-Za-z0-9]+$ ]] || { echo "no deployment id for $url" >&2; exit 1; }
    for _ in 1 2 3 4 5 6; do
      # An API error is retried like a mismatch; only the last answer fails the job.
      now="$(vapi GET "/v4/aliases/$host?projectId=$VERCEL_PROJECT_ID" | jq -r '.deploymentId // ""' || true)"
      [ "$now" = "$id" ] && { echo "$host serves $id" >&2; echo "https://$host"; exit 0; }
      sleep 5
    done
    echo "$host serves ${now:-nothing}, not $id: is the project rolled back? Undo it in the Vercel dashboard" >&2
    exit 1
    ;;
  *) echo "usage: $0 install | assemble <dir> <out> | preview <out> <pr> | address <pr> <url> | prune <pr> [<keep-url>] | production <dir> <sha> | live <url>" >&2; exit 2 ;;
esac
