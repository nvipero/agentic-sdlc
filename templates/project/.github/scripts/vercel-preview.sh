#!/usr/bin/env bash
# Vercel preview housekeeping through the REST API, for preview-deploy and
# preview-cleanup (main's definitions, environment "preview").
#
#   vercel-preview.sh alias <deployment-url> <alias-host>   move the PR's stable address
#   vercel-preview.sh prune <pr> [<keep-url>]               delete the PR's other previews
#
# Env: VERCEL_TOKEN, VERCEL_ORG_ID, VERCEL_PROJECT_ID. The token goes to curl in a
# config on stdin, never in its arguments. Only deployments that are previews
# (no target) and carry this PR's number as metadata are ever deleted, so the
# production placeholder cannot be touched.
set -euo pipefail

team=
[[ "$VERCEL_ORG_ID" == team_* ]] && team="teamId=$VERCEL_ORG_ID"

vapi() {   # vapi <method> <path> [json body]
  local sep='?'; [[ "$2" == *\?* ]] && sep='&'
  printf 'header = "Authorization: Bearer %s"\n' "$VERCEL_TOKEN" \
    | curl -fsS --max-time 30 -K - -X "$1" -H 'Content-Type: application/json' \
        ${3:+--data "$3"} "https://api.vercel.com$2${team:+$sep$team}"
}

case "${1:-}" in
  alias)
    url="${2#https://}" host="$3"
    [[ "$url" =~ ^[a-z0-9-]+\.vercel\.app$ && "$host" =~ ^[a-z0-9-]+\.vercel\.app$ ]] || { echo "bad host" >&2; exit 1; }
    vapi POST "/v2/deployments/$url/aliases" "{\"alias\":\"$host\"}" | jq -r '"alias \(.alias) set"'
    ;;
  prune)
    pr="$2" keep="${3#https://}"
    [[ "$pr" =~ ^[0-9]+$ ]] || { echo "bad PR number" >&2; exit 1; }
    vapi GET "/v7/deployments?projectId=$VERCEL_PROJECT_ID&limit=100" \
      | jq -r --arg pr "$pr" --arg keep "$keep" \
          '.deployments[] | select(.target == null and (.meta.pr // "") == $pr and .url != $keep) | .uid' \
      | while read -r uid; do
          [[ "$uid" =~ ^dpl_[A-Za-z0-9]+$ ]] || continue
          vapi DELETE "/v13/deployments/$uid" | jq -r '"\(.uid) \(.state)"'
        done
    ;;
  *) echo "usage: $0 alias <url> <host> | prune <pr> [<keep-url>]" >&2; exit 2 ;;
esac
