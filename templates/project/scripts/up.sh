#!/usr/bin/env bash
# Starts the project's agent container. Every step fails closed.
#
#   scripts/up.sh            preflight, start, open a shell in the container
#   scripts/up.sh <cmd...>   same, but run <cmd> instead of a shell
#   scripts/up.sh stop       stop the container (volumes are kept)
#
# Needs on the host: gh (logged in as the repo owner), git, op, devcontainer, docker.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Bash has already read this file, so a version pulled in by sync_clone would
# only take effect on the next run. main re-executes itself when that happens.
SELF_HASH="$(git hash-object "$REPO_DIR/scripts/up.sh")"
PROJECT="$(basename "$REPO_DIR")"
TOKEN_REF="${FACTORY_TOKEN_REF:-op://Agent Factory/${PROJECT}-github/credential}"
EXPECTED_VISIBILITY="${FACTORY_EXPECTED_VISIBILITY:-PUBLIC}"
WARN_DAYS=14

die() { echo "up.sh: REFUSING TO START: $*" >&2; exit 1; }
say() { echo "up.sh: $*" >&2; }

container_id() {
  docker ps -q --filter "label=devcontainer.local_folder=$REPO_DIR"
}

stop_container() {
  local cid
  cid="$(container_id)"
  if [ -n "$cid" ]; then docker stop "$cid" >/dev/null; fi
}

# --- 1. Preflight: GitHub protections (host, owner's gh login) ---------------
preflight() {
  local nwo visibility rules ruleset_ids id ok limit days
  nwo="$(cd "$REPO_DIR" && gh repo view --json nameWithOwner --jq .nameWithOwner)" \
    || die "cannot read repository with gh"
  NWO="$nwo"

  visibility="$(gh repo view "$nwo" --json visibility --jq .visibility)"
  [ "$visibility" = "$EXPECTED_VISIBILITY" ] \
    || die "visibility is $visibility, expected $EXPECTED_VISIBILITY"

  rules="$(gh api "repos/$nwo/rules/branches/main" --jq '[.[].type] | unique | join(" ")')" \
    || die "cannot read rules for main"
  for r in pull_request non_fast_forward deletion; do
    case " $rules " in *" $r "*) ;; *) die "rule '$r' is not active on main" ;; esac
  done

  ruleset_ids="$(gh api "repos/$nwo/rules/branches/main" --jq '[.[].ruleset_id] | unique | .[]')"
  [ -n "$ruleset_ids" ] || die "no ruleset applies to main"
  for id in $ruleset_ids; do
    ok="$(gh api "repos/$nwo/rulesets/$id" \
      --jq '.enforcement == "active" and has("bypass_actors") and (.bypass_actors | length == 0)')" \
      || die "cannot read ruleset $id"
    [ "$ok" = "true" ] || die "ruleset $id is not active or has bypass actors"
  done

  limit="$(gh api "repos/$nwo/interaction-limits")" || die "cannot read interaction limits"
  [ -n "$limit" ] && [ "$limit" != "{}" ] || die "no interaction limit is active"
  [ "$(echo "$limit" | jq -r .limit)" = "collaborators_only" ] \
    || die "interaction limit is not collaborators_only"
  days="$(echo "$limit" | jq -r '((.expires_at | fromdateiso8601) - now) / 86400 | floor')"
  [ "$days" -ge 0 ] || die "interaction limit has expired"
  if [ "$days" -lt "$WARN_DAYS" ]; then
    say "WARNING: interaction limit expires in $days days; renew it with scripts/setup-github.sh in the factory repo"
  fi
  say "preflight OK: $nwo is $visibility, ruleset active without bypass, interaction limit $days days left"
}

# --- 2. Host clone: clean main, fast-forwarded to origin/main ----------------
sync_clone() {
  local branch
  branch="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)"
  [ "$branch" = "main" ] || die "host clone is on '$branch', expected main"
  [ -z "$(git -C "$REPO_DIR" status --porcelain)" ] || die "host clone has local changes"
  git -C "$REPO_DIR" fetch -q origin main || die "git fetch failed"
  git -C "$REPO_DIR" merge -q --ff-only origin/main || die "cannot fast-forward main"
  [ "$(git -C "$REPO_DIR" rev-parse HEAD)" = "$(git -C "$REPO_DIR" rev-parse origin/main)" ] \
    || die "host clone is not at origin/main"
}

# --- 3. Token: the only secret source step ----------------------------------
read_token() {
  FACTORY_GH_TOKEN="$(op read "$TOKEN_REF")" || die "cannot read token from 1Password"
  [ -n "$FACTORY_GH_TOKEN" ] || die "empty token"
  export FACTORY_GH_TOKEN
}

# --- 4. Image: always built from the current .devcontainer/ tree -------------
build_image() {
  local dir="$1"
  shift
  FACTORY_DEVCONTAINER_TREE="$(git -C "$dir" rev-parse HEAD:.devcontainer)"
  export FACTORY_DEVCONTAINER_TREE
  devcontainer build --workspace-folder "$dir" "$@" >&2 || die "image build failed"
}

check_image_label() {
  local cid="$1" image label
  image="$(docker inspect -f '{{.Image}}' "$cid")"
  label="$(docker image inspect -f '{{index .Config.Labels "factory.devcontainer.tree"}}' "$image")"
  if [ "$label" != "$FACTORY_DEVCONTAINER_TREE" ]; then
    docker stop "$cid" >/dev/null
    die "container image was built from tree '$label', expected '$FACTORY_DEVCONTAINER_TREE'"
  fi
}

# --- 5. Container, recreated on every start ---------------------------------
start_container() {
  export FACTORY_REPO_URL="https://github.com/$NWO.git"
  devcontainer up --workspace-folder "$REPO_DIR" --remove-existing-container >&2 \
    || { stop_container; die "devcontainer up failed (firewall or workspace init)"; }
  CID="$(container_id)"
  [ -n "$CID" ] || die "container not found after start"
  check_image_label "$CID"
  [ "$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$CID")" = "no" ] \
    || { stop_container; die "container restart policy is not 'no'"; }
}

# --- 6. Probe before handing over -------------------------------------------
# factory-exec (in the image) checks the tmpfs firewall marker, managed
# settings and the network before running anything; every exec goes through it.
probe_network() {
  devcontainer exec --workspace-folder "$REPO_DIR" /usr/local/bin/factory-exec true >&2 \
    || { stop_container; die "container probe failed"; }
  say "container probe OK (firewall, network, managed settings)"
}

main() {
  if [ "${1:-}" = "stop" ]; then stop_container; say "stopped"; exit 0; fi
  for c in gh git jq op devcontainer docker; do
    command -v "$c" >/dev/null || die "'$c' is not installed"
  done
  preflight
  sync_clone
  if [ "$(git hash-object "$REPO_DIR/scripts/up.sh")" != "$SELF_HASH" ]; then
    [ -z "${FACTORY_UP_REEXEC:-}" ] || die "up.sh changed again after re-exec"
    say "up.sh changed on main; restarting with the new version"
    FACTORY_UP_REEXEC=1 exec "$REPO_DIR/scripts/up.sh" "$@"
  fi
  read_token
  build_image "$REPO_DIR"
  start_container
  probe_network
  exec devcontainer exec --workspace-folder "$REPO_DIR" /usr/local/bin/factory-exec "$@"
}

# Allow the exit check to source the functions without running main.
if [ "${FACTORY_UP_SOURCE_ONLY:-}" != "1" ]; then
  main "$@"
fi
