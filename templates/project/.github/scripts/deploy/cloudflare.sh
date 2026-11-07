#!/usr/bin/env bash
# Deployment target "cloudflare" (deploy.target in .factory/config.yaml): a
# Cloudflare Worker with static assets only, for preview-deploy, preview-cleanup
# (environment "preview") and production-deploy (environment "production"), all
# main's definitions.
#
#   cloudflare.sh install                     Wrangler; run without secrets
#   cloudflare.sh assemble <dir> <out>        the deployable output in <out>; run without secrets
#   cloudflare.sh preview <out> <pr>          deploy <out> as the PR's Preview; prints its URL
#   cloudflare.sh address <pr> <url>          the PR's stable address: the Preview URL itself
#   cloudflare.sh prune <pr> [<keep-url>]     without <keep-url>, delete the PR's Preview; needs only curl
#   cloudflare.sh production <out> <sha>      deploy <out> to production; prints the version's URL
#   cloudflare.sh live <url>                  fail unless production serves that version; prints the address
#
# <dir> holds the checked build (regular files only, with index.html). Its files
# are copied as assets, except _headers, _redirects and .assetsignore, which
# Cloudflare would read as rules. The Wrangler configuration is written here,
# without "main": no code from the build runs at the edge. deploy.spa in
# .factory/config.yaml turns on the single-page-application fallback.
#
# Addresses: the Worker is named after the repository. A PR's Preview at
# pr-<n>-<worker>.<subdomain>.workers.dev (Workers Previews, not version URLs:
# Cloudflare's advice for pull requests), production at <worker>.<subdomain>.workers.dev.
# The Worker exists from setup: creating one needs more than the token's scope.
#
# Env: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID; GITHUB_REPOSITORY. Wrangler
# reads both from its environment; curl gets the token in a config on stdin,
# never in its arguments. Only the Preview named after this PR is ever deleted.
set -euo pipefail

CLI=wrangler@4.152.0
COMPAT_DATE=2026-10-01
export WRANGLER_SEND_METRICS=false

# Lowercase letters, digits and hyphens, as Worker names.
hostpart() { printf '%s' "$1" | tr '/A-Z' '-a-z' | tr -cd 'a-z0-9-'; }

worker() {
  local repo="${GITHUB_REPOSITORY:-}" name
  name="$(hostpart "${repo#*/}")"
  [[ "$name" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || { echo "bad Worker name from '$repo'" >&2; exit 1; }
  echo "$name"
}

cfapi() {   # cfapi <method> <path below the account> <body file>: prints the HTTP status
  printf 'header = "Authorization: Bearer %s"\n' "$CLOUDFLARE_API_TOKEN" \
    | curl -sS --max-time 30 -K - -X "$1" -o "$3" -w '%{http_code}' \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID$2"
}

# deploy.spa from the .factory/config.yaml next to this script's .github/.
spa() {
  local config; config="$(cd "$(dirname "$0")/../../.." && pwd)/.factory/config.yaml"
  ruby -ryaml -e 'c = YAML.load_file(ARGV[0]); d = c.is_a?(Hash) ? c["deploy"] : nil
    puts(d.is_a?(Hash) && d["spa"] == true ? "true" : "false")' "$config"
}

case "${1:-}" in
  install)
    npm install --global --ignore-scripts "$CLI"
    ;;
  assemble)
    dir="${2:-}" out="${3:-}"
    [ -f "$dir/index.html" ] || { echo "no index.html in '$dir'" >&2; exit 1; }
    [ -n "$out" ] || { echo "no output directory" >&2; exit 1; }
    mkdir -p "$out/public"
    cp -R "$dir"/. "$out/public/"
    rm -f "$out/public/_headers" "$out/public/_redirects" "$out/public/.assetsignore"
    if [ "$(spa)" = true ]; then nf=single-page-application; else nf=404-page; fi
    jq -n --arg name "$(worker)" --arg date "$COMPAT_DATE" --arg nf "$nf" \
      '{name: $name, compatibility_date: $date, workers_dev: true, preview_urls: true,
        assets: {directory: "./public", not_found_handling: $nf}, previews: {}}' > "$out/wrangler.jsonc"
    ;;
  preview)
    dir="${2:-}" pr="${3:-}"
    [[ "$pr" =~ ^[0-9]+$ ]] || { echo "bad PR number" >&2; exit 1; }
    [ -f "$dir/wrangler.jsonc" ] || { echo "nothing assembled in $dir" >&2; exit 1; }
    name="pr-$pr-$(worker)"; [ "${#name}" -le 63 ] || { echo "$name is longer than 63 characters" >&2; exit 1; }
    log="$(mktemp)"
    # With --json, Wrangler prints its errors to stdout too.
    (cd "$dir" && wrangler preview --name "pr-$pr" --message "PR $pr" --ignore-base-config --json) > "$log" \
      || { cat "$log" >&2; exit 1; }
    # The JSON's .preview.urls holds it; taken by pattern, like vercel.sh, in case
    # Wrangler logs anything else to stdout.
    url="$(grep -oE "https://$name\.[a-z0-9-]+\.workers\.dev" "$log" | head -1 || true)"
    [ -n "$url" ] || { echo "no Preview URL for $name in the output" >&2; cat "$log" >&2; exit 1; }
    echo "$url"
    ;;
  address)
    pr="${2:-}" url="${3:-}"
    [[ "$pr" =~ ^[0-9]+$ ]] || { echo "bad PR number" >&2; exit 1; }
    [[ "$url" =~ ^https://pr-$pr-[a-z0-9-]+\.[a-z0-9-]+\.workers\.dev$ ]] || { echo "bad Preview URL" >&2; exit 1; }
    echo "$url"
    ;;
  prune)
    # A Preview keeps its newest deployment at its address, so only a closed PR
    # has anything to remove.
    pr="${2:-}" keep="${3:-}"
    [[ "$pr" =~ ^[0-9]+$ ]] || { echo "bad PR number" >&2; exit 1; }
    [ -n "$keep" ] && exit 0
    w="$(worker)" body="$(mktemp)"
    code="$(cfapi GET "/workers/workers/$w/previews/pr-$pr" "$body" || true)"
    [ "$code" = 404 ] && { echo "no Preview pr-$pr" >&2; exit 0; }
    [ "$code" = 200 ] || { echo "reading Preview pr-$pr: HTTP $code" >&2; cat "$body" >&2; exit 1; }
    urls="$(jq -r '.result.urls[]?' "$body")"
    # The API call wrangler preview delete makes: preview-cleanup installs no tools.
    code="$(cfapi DELETE "/workers/workers/$w/previews/pr-$pr" "$body" || true)"
    [ "$code" = 200 ] || { echo "deleting Preview pr-$pr: HTTP $code" >&2; cat "$body" >&2; exit 1; }
    echo "Preview pr-$pr deleted"
    # A deleted Preview has been seen serving for hours on a static-assets Worker
    # (github.com/cloudflare/developer-platform/issues/73). Behind Access, a login
    # redirect is all the public gets either way, so this sees only public serving.
    for u in $urls; do
      [[ "$u" =~ ^https://[a-z0-9.-]+$ ]] || continue
      code=
      for _ in 1 2 3 4 5 6; do
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$u" || true)"
        [ "$code" = 200 ] || break
        sleep 10
      done
      [ "$code" = 200 ] && echo "::warning::$u still serves after the delete (cloudflare/developer-platform#73)" \
        || echo "$u: $code"
    done
    ;;
  production)
    dir="${2:-}" sha="${3:-}"
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "bad commit" >&2; exit 1; }
    [ -f "$dir/wrangler.jsonc" ] || { echo "nothing assembled in $dir" >&2; exit 1; }
    log="$(mktemp)"
    (cd "$dir" && wrangler deploy --message "$sha") > "$log" || { cat "$log" >&2; exit 1; }
    w="$(worker)"
    host="$(grep -oE "https://$w\.[a-z0-9-]+\.workers\.dev" "$log" | head -1 || true)"
    version="$(sed -nE 's/.*Current Version ID: ([0-9a-f-]{36}).*/\1/p' "$log" | head -1)"
    [ -n "$host" ] && [ -n "$version" ] || { echo "no address or version in the output" >&2; cat "$log" >&2; exit 1; }
    # The version's own URL: <first 8 of its id>-<worker>.<subdomain>.workers.dev.
    echo "https://${version:0:8}-${host#https://}"
    ;;
  live)
    url="${2:-}"; url="${url#https://}"; w="$(worker)"
    [[ "$url" =~ ^([0-9a-f]{8})-($w\.[a-z0-9-]+\.workers\.dev)$ ]] || { echo "bad version URL" >&2; exit 1; }
    prefix="${BASH_REMATCH[1]}" host="${BASH_REMATCH[2]}"
    now=
    for _ in 1 2 3 4 5 6; do
      # An API error is retried like a mismatch; only the last answer fails the job.
      now="$(wrangler deployments status --name "$w" --json 2>/dev/null \
        | jq -r '[.versions[] | select(.percentage == 100) | .version_id] | if length == 1 then .[0] else "" end' || true)"
      [ "${now:0:8}" = "$prefix" ] && { echo "$host serves $now" >&2; echo "https://$host"; exit 0; }
      sleep 5
    done
    echo "$host serves ${now:-no single version}, not $prefix…" >&2
    exit 1
    ;;
  *) echo "usage: $0 install | assemble <dir> <out> | preview <out> <pr> | address <pr> <url> | prune <pr> [<keep-url>] | production <out> <sha> | live <url>" >&2; exit 2 ;;
esac
