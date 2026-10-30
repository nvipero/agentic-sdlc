#!/usr/bin/env bash
# Starts the project's agent container. Every step fails closed.
#
#   scripts/up.sh            preflight, start, open a shell in the container
#   scripts/up.sh <cmd...>   same, but run <cmd> instead of a shell
#   scripts/up.sh stop       stop the container (volumes are kept)
#   scripts/up.sh reset-workspace
#                            show the workspace content, ask for confirmation,
#                            archive the workspace volume and clone a fresh one
#
# Needs on the host: gh (logged in as the repo owner), git, op, openssl, curl, jq,
# devcontainer, docker.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$(basename "$REPO_DIR")"
# The agents' GitHub identity: a GitHub App. Its client id is not secret; its
# private key is a 1Password document that never leaves this machine.
APP_CLIENT_ID="${FACTORY_APP_CLIENT_ID:-Iv23liljNpUlSNsNl3wU}"
APP_KEY_VAULT="${FACTORY_APP_KEY_VAULT:-Agent Factory}"
APP_KEY_DOC="${FACTORY_APP_KEY_DOC:-nvipero-factory-orchestrator-key}"
# Per-project host state, outside the clone. token/ is mounted read-only into
# the container (devcontainer.json) and holds only the current one-hour token.
RUN_DIR="$HOME/.factory-run/$PROJECT"
export FACTORY_TOKEN_DIR="$RUN_DIR/token"
REFRESH_AGE=2700      # mint a new token when the current one is 45 minutes old
REFRESH_MARGIN=900    # or expires within 15 minutes
EXPECTED_VISIBILITY="${FACTORY_EXPECTED_VISIBILITY:-PUBLIC}"
WARN_DAYS=14
VOLUME="${PROJECT}-workspace"   # matches workspaceMount in devcontainer.json

# After this start has taken over the token (TOKEN_OWNED), a refusal removes it.
die() {
  echo "up.sh: REFUSING TO START: $*" >&2
  if [ -n "${TOKEN_OWNED:-}" ]; then remove_token; fi
  exit 1
}
say() { echo "up.sh: $*" >&2; }

container_id() {
  docker ps -q --filter "label=devcontainer.local_folder=$REPO_DIR"
}

stop_container() {
  local cid
  cid="$(container_id)"
  if [ -n "$cid" ]; then docker stop "$cid" >/dev/null; fi
}

# Runs a command in the container ($CID) as the agent user. No credential is
# passed: gh and git in the container read the token from the read-only token
# mount on every call. Leading "-e NAME" arguments pass variables by name. A
# terminal (-t) is used only when both stdin and stdout are one; give
# non-interactive execs </dev/null so they do not consume the caller's stdin.
box_exec() {
  local tty= envs=()
  while [ "${1:-}" = "-e" ]; do envs+=(-e "$2"); shift 2; done
  if [ -t 0 ] && [ -t 1 ]; then tty=1; fi
  docker exec -i ${tty:+-t} -u node -w /workspace ${envs[@]+"${envs[@]}"} "$CID" "$@"
}

# Removes the project's containers, running or stopped (they are recreated on every start).
remove_containers() {
  local cid
  for cid in $(docker ps -aq --filter "label=devcontainer.local_folder=$REPO_DIR"); do
    docker rm -f "$cid" >/dev/null
  done
}

# --- 1. Preflight: GitHub protections (host, owner's gh login) ---------------
preflight() {
  local nwo repo visibility branch_rules rules ruleset_ids id ok limit days scanning
  nwo="$(cd "$REPO_DIR" && gh repo view --json nameWithOwner --jq .nameWithOwner)" \
    || die "cannot read repository with gh"
  NWO="$nwo"

  # One read of the repository object for visibility and security settings.
  repo="$(gh api "repos/$nwo")" || die "cannot read repository settings"
  visibility="$(echo "$repo" | jq -r '.visibility | ascii_upcase')"
  [ "$visibility" = "$EXPECTED_VISIBILITY" ] \
    || die "visibility is $visibility, expected $EXPECTED_VISIBILITY"

  branch_rules="$(gh api "repos/$nwo/rules/branches/main")" || die "cannot read rules for main"
  rules="$(echo "$branch_rules" | jq -r '[.[].type] | unique | join(" ")')"
  for r in pull_request non_fast_forward deletion; do
    case " $rules " in *" $r "*) ;; *) die "rule '$r' is not active on main" ;; esac
  done

  ruleset_ids="$(echo "$branch_rules" | jq -r '[.[].ruleset_id] | unique | .[]')"
  [ -n "$ruleset_ids" ] || die "no ruleset applies to main"
  for id in $ruleset_ids; do
    ok="$(gh api "repos/$nwo/rulesets/$id" \
      --jq '.enforcement == "active" and has("bypass_actors") and (.bypass_actors | length == 0)')" \
      || die "cannot read ruleset $id"
    [ "$ok" = "true" ] || die "ruleset $id is not active or has bypass actors"
  done

  scanning="$(echo "$repo" | jq -r '.security_and_analysis | "\(.secret_scanning.status) \(.secret_scanning_push_protection.status)"')"
  [ "$scanning" = "enabled enabled" ] || die "secret scanning or push protection is not enabled ($scanning)"

  limit="$(gh api "repos/$nwo/interaction-limits")" || die "cannot read interaction limits"
  [ -n "$limit" ] && [ "$limit" != "{}" ] || die "no interaction limit is active"
  [ "$(echo "$limit" | jq -r .limit)" = "collaborators_only" ] \
    || die "interaction limit is not collaborators_only"
  days="$(echo "$limit" | jq -r '((.expires_at | fromdateiso8601) - now) / 86400 | floor')"
  [ "$days" -ge 0 ] || die "interaction limit has expired"
  if [ "$days" -lt "$WARN_DAYS" ]; then
    say "WARNING: interaction limit expires in $days days; renew it with scripts/setup-github.sh in the factory repo"
  fi
  # Actions stays off until step 4: a workflow run would execute outside the sandbox.
  local actions
  actions="$(gh api "repos/$nwo/actions/permissions" --jq .enabled)" || die "cannot read GitHub Actions settings"
  [ "$actions" = "false" ] \
    || die "GitHub Actions is not disabled (enabled=$actions); run scripts/setup-github.sh actions in the factory repo"
  say "preflight OK: $nwo is $visibility, ruleset active without bypass, secret scanning and push protection on, Actions disabled, interaction limit $days days left"
}

# --- 2. Host clone: clean main, equal to origin/main -------------------------
# Never updated automatically: whatever reaches main (an agent can merge until
# step 4) runs on this machine only after the owner has reviewed and pulled it.
check_clone() {
  local branch
  branch="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)"
  [ "$branch" = "main" ] || die "host clone is on '$branch', expected main"
  [ -z "$(git -C "$REPO_DIR" status --porcelain)" ] || die "host clone has local changes"
  git -C "$REPO_DIR" fetch -q origin main || die "git fetch failed"
  local ahead behind
  read -r ahead behind < <(git -C "$REPO_DIR" rev-list --left-right --count HEAD...origin/main) \
    || die "cannot compare the host clone with origin/main"
  if [ "$ahead" -gt 0 ]; then
    die "host clone main has $ahead commit(s) that are not on origin/main$([ "$behind" -gt 0 ] && echo " and is $behind behind"). main only changes through pull requests; move those commits to a branch"
  fi
  [ "$behind" -eq 0 ] \
    || die "host clone main is $behind commit(s) behind origin/main. Review the new commits (git log -p HEAD..origin/main), then pull manually (git pull --ff-only)"
}

# --- 3. Token: the only secret source step ----------------------------------
# The App key is read once per start and kept in this shell's memory (not
# exported, never on disk). No secret ever reaches a process's arguments: the
# key goes to openssl through a file descriptor, the JWT to curl through a
# config on stdin, and jq reads responses from a pipe.
read_app_key() {
  [ -n "$APP_CLIENT_ID" ] || die "FACTORY_APP_CLIENT_ID is not set"
  APP_KEY="$(op document get "$APP_KEY_DOC" --vault "$APP_KEY_VAULT")" \
    || die "cannot read the GitHub App key from 1Password"
  case "$APP_KEY" in *"PRIVATE KEY"*) ;; *) die "the 1Password document is not a private key" ;; esac
}

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# A JWT for the App, valid 9 minutes; issued 60 seconds in the past against clock skew.
app_jwt() {
  local now unsigned sig
  now="$(date +%s)"
  unsigned="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url).$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' \
    $((now - 60)) $((now + 540)) "$APP_CLIENT_ID" | b64url)"
  sig="$(printf '%s' "$unsigned" | openssl dgst -sha256 -binary -sign <(printf '%s\n' "$APP_KEY") | b64url)" \
    || return 1
  [ -n "$sig" ] || return 1
  printf '%s.%s' "$unsigned" "$sig"
}

# app_api <jwt> <method> <path> [json body]: the JWT goes in a curl config on stdin.
app_api() {
  printf 'header = "Authorization: Bearer %s"\n' "$1" \
    | curl -fsS --max-time 20 -K - -X "$2" -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" ${4:+--data "$4"} "https://api.github.com$3"
}

# Mints an installation token for this one repository with only the permissions
# the agents use, and replaces the token file atomically (write, then rename:
# the directory is mounted, so the container sees the new file).
mint_token() {
  local jwt inst resp tmp
  jwt="$(app_jwt)" || { echo "cannot sign the App JWT" >&2; return 1; }
  inst="$(app_api "$jwt" GET "/repos/$NWO/installation" | jq -r '.id // empty')"
  [ -n "$inst" ] || { echo "the App is not installed on $NWO" >&2; return 1; }
  resp="$(app_api "$jwt" POST "/app/installations/$inst/access_tokens" \
    "{\"repositories\":[\"${NWO#*/}\"],\"permissions\":{\"contents\":\"write\",\"issues\":\"write\",\"pull_requests\":\"write\",\"metadata\":\"read\"}}")" \
    || { echo "minting the installation token failed" >&2; return 1; }
  mkdir -p "$FACTORY_TOKEN_DIR" && chmod 0700 "$RUN_DIR" "$FACTORY_TOKEN_DIR"
  tmp="$(mktemp "$FACTORY_TOKEN_DIR/.token.XXXXXX")"
  printf '%s' "$resp" | jq -j '.token // empty' > "$tmp"
  [ -s "$tmp" ] || { rm -f "$tmp"; echo "the mint response has no token" >&2; return 1; }
  printf '%s' "$resp" | jq -r '.expires_at | fromdateiso8601' > "$RUN_DIR/expires_at"
  mv -f "$tmp" "$FACTORY_TOKEN_DIR/token"
}

token_needs_refresh() {
  local now exp mtime
  [ -s "$FACTORY_TOKEN_DIR/token" ] && [ -s "$RUN_DIR/expires_at" ] || return 0
  now="$(date +%s)"; exp="$(cat "$RUN_DIR/expires_at")"
  mtime="$(stat -f %m "$FACTORY_TOKEN_DIR/token")"
  [ $((now - mtime)) -ge "$REFRESH_AGE" ] || [ $((exp - now)) -le "$REFRESH_MARGIN" ]
}

# Removes the token, so a stopped container leaves no credential behind.
remove_token() { rm -f "$FACTORY_TOKEN_DIR/token" "$RUN_DIR/expires_at"; }

stop_refresher() {
  local pid
  pid="$(cat "$RUN_DIR/refresher.pid" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
  rm -f "$RUN_DIR/refresher.pid"
}

# Runs in the background while container $CID runs, checking every minute, so a
# Mac waking from sleep gets a new token within a minute. It survives the
# terminal closing; up.sh stop or the next start ends it. Exits with the
# container and removes the token.
start_refresher() {
  (
    trap '' HUP
    trap 'remove_token; exit 0' TERM
    while [ "$(docker inspect -f '{{.State.Running}}' "$CID" 2>/dev/null)" = "true" ]; do
      if token_needs_refresh; then
        mint_token && echo "$(date -u +%FT%TZ) refreshed" || echo "$(date -u +%FT%TZ) refresh FAILED"
      fi
      sleep 60 & wait $!
    done
    remove_token
  ) >>"$RUN_DIR/refresher.log" 2>&1 </dev/null &
  echo $! > "$RUN_DIR/refresher.pid"
  disown
}

# --- 4. Image: always built from the current .devcontainer/ tree -------------
build_image() {
  local dir="$1"
  shift
  FACTORY_DEVCONTAINER_TREE="$(git -C "$dir" rev-parse HEAD:.devcontainer)"
  export FACTORY_DEVCONTAINER_TREE
  devcontainer build --workspace-folder "$dir" "$@" >&2 || die "image build failed"
}

# No side effects: prints the problem and returns non-zero on a mismatch.
check_image_label() {
  local cid="$1" image label
  image="$(docker inspect -f '{{.Image}}' "$cid")"
  label="$(docker image inspect -f '{{index .Config.Labels "factory.devcontainer.tree"}}' "$image")"
  if [ "$label" != "$FACTORY_DEVCONTAINER_TREE" ]; then
    echo "container image was built from tree '$label', expected '$FACTORY_DEVCONTAINER_TREE'"
    return 1
  fi
}

# --- 5. Container, recreated on every start ---------------------------------
start_container() {
  export FACTORY_REPO_URL="https://github.com/$NWO.git"   # not secret; only the workspace init gets it
  devcontainer up --workspace-folder "$REPO_DIR" --remove-existing-container >&2 \
    || { stop_container; die "devcontainer up failed"; }
  CID="$(container_id)"
  [ -n "$CID" ] || die "container not found after start"
  local mismatch
  mismatch="$(check_image_label "$CID")" || { stop_container; die "$mismatch"; }
  [ "$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$CID")" = "no" ] \
    || { stop_container; die "container restart policy is not 'no'"; }
  # Waits for the firewall marker, then clones or checks the workspace.
  box_exec -e FACTORY_REPO_URL /usr/local/bin/init-workspace.sh </dev/null >&2 \
    || { stop_container; die "workspace init failed"; }
}

# --- 6. Probe before handing over -------------------------------------------
# factory-exec (in the image) checks the tmpfs firewall marker, managed
# settings and the network before running anything; every exec goes through it.
probe_network() {
  box_exec /usr/local/bin/factory-exec true </dev/null >&2 \
    || { stop_container; die "container probe failed"; }
  say "container probe OK (firewall, network, managed settings)"
}

# --- Workspace reset: archives the old workspace, never deletes it -----------
# The image built from the current .devcontainer/ tree (after build_image).
workspace_image() {
  docker images -q --filter "label=factory.devcontainer.tree=$FACTORY_DEVCONTAINER_TREE" | head -1
}

# Runs a bash command against the workspace volume in a throwaway container
# without network. --read-only first mounts the volume read-only; other
# docker run options go before the command.
run_on_volume() {
  local mode="" cmd image
  if [ "${1:-}" = "--read-only" ]; then mode=":ro"; shift; fi
  cmd="${!#}"
  image="$(workspace_image)"
  [ -n "$image" ] || { echo "no image for tree $FACTORY_DEVCONTAINER_TREE" >&2; return 1; }
  docker run --rm --network none --entrypoint bash -v "$VOLUME:/workspace$mode" "${@:1:$#-1}" "$image" \
    -c "cd /workspace && $cmd"
}

# Informational: the old workspace is archived, not deleted, so this does not
# have to be complete. Lists are cut at 50 lines with a count of the rest.
workspace_report() {
  run_on_volume --read-only -e GIT_OPTIONAL_LOCKS=0 '
    list() { local all; all="$(cat)"; [ -z "$all" ] && return; echo "$all" | head -50 | sed "s/^/    /";
             n=$(echo "$all" | wc -l); [ "$n" -gt 50 ] && echo "    ... and $((n - 50)) more"; return 0; }
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
      echo "  no usable git repository; top-level entries:"; ls -A | list; exit 0
    fi
    echo "  current HEAD: $(git symbolic-ref -q --short HEAD || echo detached) at $(git rev-parse -q --verify --short HEAD || echo "no commits (orphan or unborn branch)")"
    echo "  local branches (upstream and ahead/behind as of the last fetch):"
    git for-each-ref --format="%(refname:short) %(upstream:short) %(upstream:track)" refs/heads | list
    echo "  commits on no remote branch, including a detached HEAD (as of the last fetch):"
    { if git rev-parse -q --verify HEAD >/dev/null; then git log --oneline HEAD --branches --not --remotes;
      else git log --oneline --branches --not --remotes; fi; } 2>/dev/null | list
    echo "  stashes:"
    git stash list 2>/dev/null | list
    echo "  uncommitted, untracked and ignored files:"
    git status --porcelain --ignored 2>/dev/null | list
  '
}

ARCHIVE_DONE_MARKER=.factory-archive-complete

# Ctrl-C or a closed terminal during the copy: stop the copy and remove the
# incomplete archive this run created. The workspace itself is untouched.
abort_archive() {
  trap - INT TERM HUP
  docker rm -f "$ARCHIVER" >/dev/null 2>&1 || true
  if docker volume rm "$ARCHIVE" >/dev/null 2>&1; then
    die "interrupted; the incomplete archive $ARCHIVE was removed and $VOLUME was not changed"
  fi
  die "interrupted; could NOT remove the incomplete archive $ARCHIVE (it has no $ARCHIVE_DONE_MARKER); $VOLUME was not changed"
}

reset_workspace() {
  local answer
  if ! docker volume inspect "$VOLUME" >/dev/null 2>&1; then
    say "no workspace volume $VOLUME; a fresh clone is made on start"
    return
  fi
  # Unique per run, so two resets can never share (or delete) an archive.
  ARCHIVE="${VOLUME}-archive-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  ARCHIVER="${VOLUME}-archiver-$$"
  say "reset-workspace: volume $VOLUME will be ARCHIVED as $ARCHIVE and replaced by a fresh clone of $NWO main."
  say "Its current content (read-only report; everything stays in the archive):"
  workspace_report >&2 || die "cannot inspect the workspace; nothing was changed"
  if ! (exec </dev/tty) 2>/dev/null; then
    die "reset-workspace needs an interactive terminal to confirm; nothing was changed"
  fi
  printf 'Type the repository name (%s) to archive and reset the workspace: ' "$NWO" >/dev/tty
  read -r answer </dev/tty || answer=""
  [ "$answer" = "$NWO" ] || die "confirmation did not match; nothing was changed"
  # Stop only now. The archive is copied from the stopped workspace, so
  # anything written before this point, after the report too, is kept.
  remove_containers
  ! docker volume inspect "$ARCHIVE" >/dev/null 2>&1 \
    || die "archive volume $ARCHIVE already exists; the workspace was not changed"
  docker volume create "$ARCHIVE" >/dev/null || die "cannot create $ARCHIVE; the workspace was not changed"
  trap abort_archive INT TERM HUP
  # Copy, then compare paths, types, modes, owners, symlink targets and file
  # contents of both volumes in one container. Both manifests must be
  # non-empty, so a broken tool cannot make the comparison pass vacuously.
  # The completion marker is written only after the comparison succeeds.
  if ! run_on_volume --read-only -u root --name "$ARCHIVER" -v "$ARCHIVE:/archive" '
      set -euo pipefail
      cp -a /workspace/. /archive/
      manifest() { cd "$1" && find . -printf "%p %y %m %U %G %l\n" | LC_ALL=C sort &&
                   find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum; }
      a="$(manifest /workspace)"; b="$(manifest /archive)"
      if [ "$(printf "%s\n" "$a" | grep -c .)" -le 1 ] || [ "$a" != "$b" ]; then exit 1; fi
      date -u +%Y-%m-%dT%H:%M:%SZ > "/archive/'"$ARCHIVE_DONE_MARKER"'"'; then
    trap - INT TERM HUP
    if docker volume rm "$ARCHIVE" >/dev/null 2>&1; then
      die "copying to $ARCHIVE failed or did not match; the incomplete copy was removed and $VOLUME was not changed"
    fi
    die "copying to $ARCHIVE failed or did not match, and the incomplete copy could NOT be removed (it has no $ARCHIVE_DONE_MARKER); $VOLUME was not changed"
  fi
  trap - INT TERM HUP
  docker volume rm "$VOLUME" >/dev/null || die "cannot remove $VOLUME (archive $ARCHIVE is complete)"
  say "archived to volume $ARCHIVE (complete: contains $ARCHIVE_DONE_MARKER; remove it yourself with: docker volume rm $ARCHIVE); cloning a fresh workspace"
}

main() {
  if [ "${1:-}" = "stop" ]; then stop_refresher; stop_container; remove_token; say "stopped"; exit 0; fi
  for c in gh git jq op openssl curl devcontainer docker; do
    command -v "$c" >/dev/null || die "'$c' is not installed"
  done
  preflight
  check_clone
  read_app_key
  # The next start recreates the container, so the old refresher goes now.
  stop_refresher
  TOKEN_OWNED=1
  mint_token || die "cannot mint a GitHub App token"
  build_image "$REPO_DIR"
  if [ "${1:-}" = "reset-workspace" ]; then
    reset_workspace
    set -- true
  fi
  start_container
  start_refresher
  probe_network
  box_exec /usr/local/bin/factory-exec "$@"
}

# Allow the exit check to source the functions without running main.
if [ "${FACTORY_UP_SOURCE_ONLY:-}" != "1" ]; then
  main "$@"
fi
