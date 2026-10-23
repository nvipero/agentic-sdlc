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
# Needs on the host: gh (logged in as the repo owner), git, op, devcontainer, docker.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$(basename "$REPO_DIR")"
TOKEN_REF="${FACTORY_TOKEN_REF:-op://Agent Factory/${PROJECT}-github/credential}"
EXPECTED_VISIBILITY="${FACTORY_EXPECTED_VISIBILITY:-PUBLIC}"
WARN_DAYS=14
VOLUME="${PROJECT}-workspace"   # matches workspaceMount in devcontainer.json

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

# Runs a command in the container ($CID) as the agent user. The token is passed
# by name only (-e GH_TOKEN): the docker client reads the value from its own
# environment, so it never appears in any process's argument list. Leading
# "-e NAME" arguments pass more variables by name. A terminal (-t) is used only
# when both stdin and stdout are one; give non-interactive execs </dev/null so
# they do not consume the caller's stdin.
box_exec() {
  local tty= envs=(-e GH_TOKEN)
  while [ "${1:-}" = "-e" ]; do envs+=(-e "$2"); shift 2; done
  if [ -t 0 ] && [ -t 1 ]; then tty=1; fi
  GH_TOKEN="$FACTORY_GH_TOKEN" docker exec -i ${tty:+-t} -u node -w /workspace "${envs[@]}" "$CID" "$@"
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
read_token() {
  # Not exported: only box_exec hands it to the docker client, by name.
  FACTORY_GH_TOKEN="$(op read "$TOKEN_REF")" || die "cannot read token from 1Password"
  [ -n "$FACTORY_GH_TOKEN" ] || die "empty token"
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
  if [ "${1:-}" = "stop" ]; then stop_container; say "stopped"; exit 0; fi
  for c in gh git jq op devcontainer docker; do
    command -v "$c" >/dev/null || die "'$c' is not installed"
  done
  preflight
  check_clone
  read_token
  build_image "$REPO_DIR"
  if [ "${1:-}" = "reset-workspace" ]; then
    reset_workspace
    set -- true
  fi
  start_container
  probe_network
  box_exec /usr/local/bin/factory-exec "$@"
}

# Allow the exit check to source the functions without running main.
if [ "${FACTORY_UP_SOURCE_ONLY:-}" != "1" ]; then
  main "$@"
fi
