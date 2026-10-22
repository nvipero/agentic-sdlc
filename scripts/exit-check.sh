#!/usr/bin/env bash
# Step 1 exit check. Runs on the host against a project whose container was
# started with scripts/up.sh. Prints PASS/FAIL lines; raw output may contain
# host details, so redact it (scripts/redact.sh) before publishing.
#
#   scripts/exit-check.sh <path-to-project-clone> <factory-owner/repo>
#
# Side effects:
# - cleaned up: one branch and one draft PR on the project (agent token
#   positive test), a throwaway local branch and worktree, a test image,
#   container restarts. Nothing is merged.
# - NOT cleaned up, on purpose: every run tests reset-workspace for real.
#   The project's workspace is archived to <repo>-workspace-archive-<time>
#   (a full copy, named in the output) and replaced by a fresh clone. Run it
#   when the workspace holds no work you need, and remove old archives with
#   docker volume rm. Nothing is deleted by the check.
set -uo pipefail

REPO="$(cd "${1:?project clone path}" && pwd)"
for c in expect perl; do command -v "$c" >/dev/null || { echo "exit-check: '$c' is not installed" >&2; exit 2; }; done
FACTORY_NWO="${2:?factory owner/repo}"
FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0

pass() { echo "PASS  $1${2:+ — $2}"; }
fail() { echo "FAIL  $1${2:+ — $2}"; FAILS=$((FAILS + 1)); }
skip() { echo "SKIP  $1${2:+ — $2}"; }   # not applicable here; not counted as a pass
section() { echo; echo "## $1"; }

# Load up.sh functions (read_token, build_image, check_image_label, ...).
# shellcheck source=/dev/null
FACTORY_UP_SOURCE_ONLY=1 source "$REPO/scripts/up.sh"
read_token
set +e   # up.sh enables errexit; checks here must keep going after a failure
NWO="$(cd "$REPO" && gh repo view --json nameWithOwner --jq .nameWithOwner)"
export FACTORY_REPO_URL="https://github.com/$NWO.git"
export FACTORY_DEVCONTAINER_TREE="$(git -C "$REPO" rev-parse HEAD:.devcontainer)"

CID="$(container_id)"   # container_id comes from up.sh
[ -n "$CID" ] || { echo "no running container; start it with scripts/up.sh first" >&2; exit 2; }

# Run a command inside the container as the agent user.
in_box() { devcontainer exec --workspace-folder "$REPO" bash -c "$1" 2>&1; }

# expect_fail <name> <command> <pattern>: command must fail and print pattern.
expect_fail() {
  local out rc
  out="$(in_box "$2")"; rc=$?
  if [ "$rc" -ne 0 ] && echo "$out" | grep -qE "$3"; then pass "$1" "$(echo "$out" | grep -E "$3" | head -1)"
  else fail "$1" "rc=$rc: $(echo "$out" | tail -1)"; fi
}
expect_ok() {
  local out rc
  out="$(in_box "$2")"; rc=$?
  if [ "$rc" -eq 0 ]; then pass "$1" "$(echo "$out" | tail -1)"; else fail "$1" "rc=$rc: $(echo "$out" | tail -1)"; fi
}

echo "# Step 1 exit check"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "project: $NWO  factory: $FACTORY_NWO"
echo "devcontainer tree: $FACTORY_DEVCONTAINER_TREE"
echo "claude: $(in_box 'claude --version' | tail -1)"

section "Factory definitions cannot be modified"
for p in .factory .claude .github .devcontainer; do
  expect_fail "write to $p/ is refused" "touch /workspace/$p/exit-check-probe" "Read-only file system"
done
expect_fail "write to CLAUDE.md is refused" "echo x >> /workspace/CLAUDE.md" "Read-only file system"
expect_ok   "managed settings are readable by the agent (Claude Code skips unreadable ones)" \
  "jq -c .permissions.deny /etc/claude-code/managed-settings.json"
expect_fail "managed settings are not writable" "echo x >> /etc/claude-code/managed-settings.json" "Permission denied"
expect_fail "allowlist in image is not writable" "echo x >> /etc/factory/allowlist.txt" "Permission denied"
expect_ok   "scripts/up.sh is not present" "test ! -e /workspace/scripts/up.sh && echo absent"
expect_ok   ".git is on the workspace volume, not the host" \
  "findmnt -no SOURCE,FSTYPE -T /workspace/.git | grep -v sshfs"
expect_ok   "overlays are hidden from git" "cd /workspace && test -z \"\$(git status --porcelain)\" && echo clean"
expect_ok   "sudo allows only the firewall script" \
  "sudo -l | sed -n '/may run/,\$p' | grep -c NOPASSWD | grep -qx 1 && sudo -l | grep -o '/usr/local/bin/init-firewall.sh'"
expect_fail "iptables as agent is refused" "iptables -F" "Permission denied|must be root"
expect_ok   "no claude binary under /home/node" \
  "test -z \"\$(find /home/node -type f -name claude 2>/dev/null)\" && echo none && ls -l /usr/bin/claude | cut -d' ' -f1,3,4"

section "Network allowlist"
for u in https://example.com https://google.com https://1.1.1.1; do
  expect_fail "$u is blocked" "curl -sS --max-time 5 -o /dev/null $u" "curl: \([0-9]+\)"
done
expect_fail "outside DNS resolver is blocked" "dig +time=3 +tries=1 @8.8.8.8 example.com" "timed out|no servers|unreachable|communications error"
expect_fail "host gateway is blocked" \
  "gw=\$(ip route | awk '/default/ {print \$3}'); curl -sS --max-time 5 -o /dev/null http://\$gw/" "curl: \([0-9]+\)"
for h in host.lima.internal host.docker.internal; do
  out="$(in_box "curl -sS --max-time 5 -o /dev/null http://$h/")"; rc=$?
  case "$out" in
    *"curl: (6)"*) skip "$h is blocked" "the name does not resolve on this runtime" ;;
    *"curl: (7)"*|*"curl: (28)"*) pass "$h is blocked by the firewall" "$(echo "$out" | tail -1)" ;;
    *) fail "$h is blocked" "rc=$rc: $(echo "$out" | tail -1)" ;;
  esac
done
if in_box "ip -6 addr show lo | grep -q '::1'" >/dev/null; then
  expect_ok "IPv6 loopback is open" \
    "node -e \"const h=require('http');setTimeout(()=>{console.log('timeout');process.exit(1)},5000);const s=h.createServer((q,r)=>r.end()).listen(8765,'::1',()=>h.get('http://[::1]:8765/',r=>{console.log('http://[::1] '+r.statusCode);s.close();process.exit(0)}).on('error',e=>{console.log(e.message);process.exit(1)}))\""
else
  skip "IPv6 loopback is open" "the container has no IPv6"
fi
# Each allowed host must answer with the status it gives without credentials (GitHub: with the token).
expect_ok "https://api.anthropic.com is reachable (404 expected for the bare host)" \
  "c=\$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' https://api.anthropic.com); echo \$c; [ \$c = 404 ]"
expect_ok "https://api.github.com/zen is reachable (authenticated, 200 expected)" \
  "c=\$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' -H \"Authorization: Bearer \$GH_TOKEN\" https://api.github.com/zen); echo \$c; [ \$c = 200 ]"
expect_ok "https://registry.npmjs.org/ is reachable (200 expected)" \
  "c=\$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' https://registry.npmjs.org/); echo \$c; [ \$c = 200 ]"

section "Network stays closed when the firewall fails"
docker exec -u root "$CID" sh -c 'printf "api.github.com\nno-such-host.invalid\n" > /tmp/bad-allowlist'
out="$(docker exec -u root -e FACTORY_ALLOWLIST_FILE=/tmp/bad-allowlist "$CID" /usr/local/bin/init-firewall.sh 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then pass "firewall exits non-zero on resolution failure" "$(echo "$out" | tail -1)"; else fail "firewall exits non-zero on resolution failure"; fi
expect_fail "api.github.com unreachable after failed firewall run" "curl -sS --max-time 5 -o /dev/null https://api.github.com/zen" "curl: \([0-9]+\)"
expect_fail "firewall marker removed after failure" "test -f /run/firewall-ok" ""
out="$(docker exec "$CID" bash -c 'FACTORY_ALLOWLIST_FILE=/tmp/bad-allowlist sudo /usr/local/bin/init-firewall.sh' 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then pass "agent cannot pass an allowlist override through sudo" "$(echo "$out" | tail -1)"; else fail "agent cannot pass an allowlist override through sudo" "$out"; fi
expect_fail "sudo refuses the firewall script with arguments" "sudo -n /usr/local/bin/init-firewall.sh /tmp/bad-allowlist" "not allowed|password is required|may not run"
docker exec -u root "$CID" rm -f /tmp/bad-allowlist
expect_ok "network restored by a normal firewall run (authenticated, 200 expected)" \
  "c=\$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' -H \"Authorization: Bearer \$GH_TOKEN\" https://api.github.com/zen); echo \$c; [ \$c = 200 ]"
docker exec -u root "$CID" rm -f /run/firewall-ok
out="$(devcontainer exec --workspace-folder "$REPO" /usr/local/bin/factory-exec true 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "REFUSING: firewall marker missing" \
  && pass "exec guard refuses without the firewall marker" "$(echo "$out" | grep REFUSING)" || fail "exec guard without marker" "$out"
docker exec -u root "$CID" /usr/local/bin/init-firewall.sh >/dev/null 2>&1 \
  || { fail "firewall restore after exec guard test"; echo "RESULT: aborted, network not restored"; exit 1; }

# Waits until the container has a firewall marker or has stopped; prints "marker" or "stopped".
wait_marker_or_stop() {
  local i
  for i in $(seq 1 90); do
    [ "$(docker inspect -f '{{.State.Running}}' "$CID")" = "true" ] || { echo stopped; return; }
    docker exec "$CID" test -f /run/firewall-ok 2>/dev/null && { echo marker; return; }
    sleep 1
  done
  echo timeout
}

section "Restarts: no automatic restart, firewall on every start"
policy="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$CID")"
[ "$policy" = "no" ] && pass "restart policy is 'no'" || fail "restart policy" "$policy"
expect_ok "firewall marker is on tmpfs" "findmnt -no FSTYPE -T /run/firewall-ok | grep -x tmpfs"
pid1="$(docker exec "$CID" cat /proc/1/comm)"
[ "$pid1" = "docker-init" ] && pass "PID 1 is docker-init (signals are forwarded)" || fail "PID 1" "$pid1"
before="$(docker exec "$CID" date +%s)"   # container clock, not the host's
t0="$(date +%s)"
docker restart "$CID" >/dev/null
stop_secs=$(( $(date +%s) - t0 ))
[ "$stop_secs" -lt 8 ] && pass "docker restart completes without waiting for SIGKILL" "${stop_secs}s" || fail "restart took ${stop_secs}s"
case "$(wait_marker_or_stop)" in
  marker)
    expect_ok "after a manual docker restart: fresh marker, example.com blocked" \
      "m=\$(stat -c %Y /run/firewall-ok) && test \$m -ge $before && ! curl -s --max-time 5 -o /dev/null https://example.com && echo \"marker from \$(date -d @\$m +%T), example.com blocked\"" ;;
  stopped)
    pass "after a manual docker restart the container is not running (firewall failed, container stopped)"
    "$REPO/scripts/up.sh" true >/dev/null 2>&1 && CID="$(container_id)" || { echo "RESULT: aborted, cannot restart container"; exit 1; } ;;
  *)
    fail "after a manual docker restart: no marker within 90s and still running" ;;
esac
docker rm -f exit-check-fw-fail >/dev/null 2>&1
if docker run -d --name exit-check-fw-fail "$(docker inspect -f '{{.Image}}' "$CID")" >/dev/null; then
  for _ in $(seq 1 60); do
    [ "$(docker inspect -f '{{.State.Running}}' exit-check-fw-fail)" = "false" ] && break
    sleep 1
  done
  state="$(docker inspect -f 'running={{.State.Running}} exit={{.State.ExitCode}}' exit-check-fw-fail)"
  log="$(docker logs exit-check-fw-fail 2>&1 | tail -1)"
  [ "$state" = "running=false exit=1" ] && pass "firewall failure at start stops the container (run without NET_ADMIN)" "$state; $log" \
    || fail "firewall failure at start" "$state; $log"
else
  fail "firewall failure at start" "docker run failed"
fi
docker rm -f exit-check-fw-fail >/dev/null 2>&1

section "Visibility: nothing outside the project workspace"
echo '```'
in_box "findmnt -rno TARGET,FSTYPE,OPTIONS | grep -E '^/workspace|^/home/node' "
echo '```'
expect_ok "mounts: only workspace volume, 5 read-only overlays, Claude volume" \
  "n=\$(findmnt -rno TARGET | grep -cE '^/workspace|^/home/node'); ro=\$(findmnt -rno TARGET,OPTIONS | grep -E '^/workspace/' | grep -c ' ro,'); test \$n -eq 7 -a \$ro -eq 5 && echo \"\$n mounts, \$ro read-only\""
expect_ok "no host home, Docker socket or SSH keys" \
  "test ! -e /Users -a ! -S /var/run/docker.sock -a ! -e /home/node/.ssh && test -z \"\$(find / -xdev -name docker.sock 2>/dev/null)\" && echo none"
expect_ok "credential-like env vars: only GH_TOKEN" \
  "env | cut -d= -f1 | grep -iE 'token|secret|key|pass|cred|auth' | tr '\n' ' '; test \"\$(env | cut -d= -f1 | grep -iE 'token|secret|key|pass|cred|auth')\" = GH_TOKEN"

section "Token on disk"
hits="$( { docker inspect "$CID"; docker image inspect "$(docker inspect -f '{{.Image}}' "$CID")"; } | grep -cFf <(printf '%s' "$FACTORY_GH_TOKEN") || true)"
if [ "$hits" = "0" ]; then pass "token not in docker inspect (container or image)"; else fail "token found in docker inspect" "$hits matching lines"; fi

section "Agent token reach (observed behaviour)"
BR="exit-check-$(date +%s)"
expect_ok "agent token can push a branch" \
  "cd /workspace && git switch -q -c $BR && git commit -q --allow-empty -m 'chore: exit check probe' && git push -q origin $BR 2>&1 && echo pushed $BR"
expect_ok "agent token can open a draft PR" \
  "cd /workspace && gh pr create --draft --base main --head $BR --title 'exit check: agent token probe (will be closed)' --body 'Automated step 1 exit check. Closed without merging.'"
# A fast-forward commit on top of origin/main, so only the ruleset can reject it.
expect_fail "agent token cannot push to main (ruleset, fast-forward commit)" \
  "cd /workspace && git fetch -q origin main && c=\$(git commit-tree 'origin/main^{tree}' -p origin/main -m 'chore: exit check probe') && git push origin \$c:refs/heads/main" \
  "GH013|rule violations|protected"
expect_fail "agent token cannot create a ruleset" \
  "gh api -X POST repos/$NWO/rulesets -f name=exit-check-probe" "HTTP 403|HTTP 404"
expect_fail "agent token cannot change interaction limits" \
  "gh api -X PUT repos/$NWO/interaction-limits -f limit=invalid" "HTTP 403|HTTP 404"
expect_fail "agent token cannot change repository settings" \
  "gh api -X PATCH repos/$NWO --input - <<< '{}'" "HTTP 403|HTTP 404"
expect_fail "agent token cannot push to the factory repo" \
  "cd /workspace && git push --dry-run https://github.com/$FACTORY_NWO.git HEAD:refs/heads/exit-check-probe" "403|denied|not found"
in_box "cd /workspace && gh pr close $BR --delete-branch --comment 'Exit check finished; closing without merge.' >/dev/null 2>&1; git switch -q main; git branch -q -D $BR" >/dev/null
gh api "repos/$NWO/branches/$BR" >/dev/null 2>&1 && fail "probe branch cleaned up" || pass "probe branch and PR cleaned up (closed, not merged)"
expect_ok "merge deny rule active in bypass mode (claude -p, permission_denials)" \
  "cd /workspace && claude -p --dangerously-skip-permissions --output-format json 'Run exactly this shell command with the Bash tool: gh pr merge --help. Then reply OK.' < /dev/null | jq -ce '[.permission_denials[] | select(.tool_name == \"Bash\" and (.tool_input.command | startswith(\"gh pr merge\")))] | if length > 0 then .[0] | {tool_name, command: .tool_input.command} else error(\"no denial recorded\") end'"

section "Protections through the API (owner login)"
for r in "$NWO" "$FACTORY_NWO"; do
  echo "### $r"
  echo '```'
  "$FACTORY_DIR/scripts/setup-github.sh" status "$r"
  echo '```'
  ok="$(gh api "repos/$r/rules/branches/main" --jq '[.[].type] | (index("pull_request") != null and index("non_fast_forward") != null and index("deletion") != null)')"
  [ "$ok" = "true" ] && pass "$r: pull_request, non_fast_forward, deletion active on main" || fail "$r: rules on main"
  ok="$(gh api "repos/$r/rulesets" --jq '.[].id' | while read -r id; do gh api "repos/$r/rulesets/$id" --jq 'has("bypass_actors") and (.bypass_actors|length==0)'; done | sort -u)"
  [ "$ok" = "true" ] && pass "$r: no bypass actors" || fail "$r: bypass actors" "$ok"
done

section "Image is rebuilt when .devcontainer/ changes"
# Leftovers from an aborted run: the worktree that has the branch checked out, then the branch.
old_wt="$(git -C "$REPO" worktree list --porcelain | awk '/^worktree /{w=$2} /^branch refs\/heads\/exit-check-rebuild$/{print w}')"
[ -z "$old_wt" ] || git -C "$REPO" worktree remove --force "$old_wt"
git -C "$REPO" worktree prune
git -C "$REPO" branch -q -D exit-check-rebuild 2>/dev/null
WT_PARENT="$(mktemp -d)"
WT="$WT_PARENT/wt"
git -C "$REPO" worktree add -q -b exit-check-rebuild "$WT" HEAD
jq '.permissions.deny += ["Bash(exit-check-probe *)"]' "$WT/.devcontainer/managed-settings.json" > "$WT/ms.json" \
  && mv "$WT/ms.json" "$WT/.devcontainer/managed-settings.json"
git -C "$WT" commit -q -am "test: change managed settings (local only)"
NEW_TREE="$(git -C "$WT" rev-parse HEAD:.devcontainer)"
( build_image "$WT" --image-name factory-exit-check-rebuild:latest ) >/dev/null 2>&1
label="$(docker image inspect -f '{{index .Config.Labels "factory.devcontainer.tree"}}' factory-exit-check-rebuild:latest 2>/dev/null)"
[ "$label" = "$NEW_TREE" ] && pass "rebuilt image carries the new tree label" "$NEW_TREE" || fail "rebuilt image label" "got '$label', want '$NEW_TREE'"
docker run --rm --entrypoint cat factory-exit-check-rebuild:latest /etc/claude-code/managed-settings.json | grep -q 'exit-check-probe' \
  && pass "changed managed settings are in the rebuilt image" || fail "changed managed settings in rebuilt image"
out="$( (FACTORY_DEVCONTAINER_TREE="$NEW_TREE"; check_image_label "$CID") 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "expected '$NEW_TREE'" && pass "image tree mismatch is detected (start_container then stops and refuses)" "$(echo "$out" | tail -1)" \
  || fail "label mismatch detection" "$out"
[ "$(container_id)" = "$CID" ] && pass "the mismatch check itself has no side effects" || fail "mismatch check stopped the container"
git -C "$REPO" worktree remove --force "$WT"; git -C "$REPO" branch -q -D exit-check-rebuild; rm -rf "$WT_PARENT"
docker rmi -f factory-exit-check-rebuild:latest >/dev/null 2>&1

section "up.sh fails closed"
out="$(FACTORY_EXPECTED_VISIBILITY=PRIVATE "$REPO/scripts/up.sh" true 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "REFUSING TO START: visibility" && pass "preflight refuses on unexpected visibility" "$(echo "$out" | grep REFUSING)" \
  || fail "preflight refusal" "$out"
[ "$(container_id)" = "$CID" ] && pass "preflight refusal leaves the running container untouched" "$CID" \
  || fail "preflight refusal changed the container" "before '$CID', after '$(container_id)'"
out="$( (FACTORY_GH_TOKEN=""; export FACTORY_GH_TOKEN; NWO="$NWO"; start_container) 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "REFUSING TO START: devcontainer up failed" && pass "up.sh aborts when postStartCommand fails" "$(echo "$out" | grep -E 'init-workspace|REFUSING' | tail -2 | tr '\n' ' ')" \
  || fail "postStartCommand failure abort" "$(echo "$out" | tail -3)"
[ -z "$(container_id)" ] && pass "no container left running after failed start" || fail "container running after failed start"

section "Workspace is never deleted automatically"
# run_on_volume and workspace_image come from up.sh, so both use the same image and mount.
"$REPO/scripts/up.sh" true >/dev/null 2>&1 && CID="$(container_id)" || { echo "RESULT: aborted, cannot start container"; exit 1; }
head_before="$(in_box "cd /workspace && echo exit-check > src/exit-check-sentinel && echo exit-check-ignored >> .git/info/exclude && touch exit-check-ignored && git rev-parse HEAD" | tail -1)"
if "$REPO/scripts/up.sh" true >/dev/null 2>&1 && [ -n "$(container_id)" ] && [ "$(container_id)" != "$CID" ]; then
  CID="$(container_id)"
  out="$(in_box "cd /workspace && cat src/exit-check-sentinel && git rev-parse HEAD")"
  [ "$out" = "$(printf 'exit-check\n%s' "$head_before")" ] \
    && pass "an existing workspace (cloned before any marker existed) survives a restart unchanged" "new container, HEAD ${head_before:0:12}, untracked file kept" \
    || fail "workspace changed across restart" "$out"
else
  fail "restart for the workspace survival check" "up.sh did not recreate the container"
fi
in_box "cd /workspace && git switch -q --orphan exit-check-orphan" >/dev/null
out="$("$REPO/scripts/up.sh" true 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "HEAD does not resolve" && echo "$out" | grep -q "reset-workspace" \
  && pass "unresolvable HEAD (orphan branch) is reported and the start refused" "$(echo "$out" | grep -o 'STOPPING:.*' | head -1 | cut -c1-140)" \
  || fail "unresolvable HEAD report" "$(echo "$out" | grep -E 'init-workspace|REFUSING' | tail -3)"
out="$(run_on_volume "git symbolic-ref HEAD; cat src/exit-check-sentinel; git rev-parse --verify -q main" 2>&1)"
[ "$out" = "$(printf 'refs/heads/exit-check-orphan\nexit-check\n%s' "$head_before")" ] \
  && pass "the workspace with an unresolvable HEAD was left untouched" "HEAD -> exit-check-orphan, main and untracked file intact" \
  || fail "workspace with unresolvable HEAD was changed" "$out"
archives_before="$(docker volume ls -q --filter "name=^${VOLUME}-archive-" | sort)"
# No controlling terminal: setsid must succeed, or the check could prompt on the real terminal.
out="$(perl -MPOSIX -e 'POSIX::setsid() or die "setsid failed: $!\n"; exec @ARGV' "$REPO/scripts/up.sh" reset-workspace </dev/null 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "needs an interactive terminal to confirm; nothing was changed" \
  && echo "$out" | grep -q "current HEAD: exit-check-orphan at no commits" && echo "$out" | grep -q '!! exit-check-ignored' \
  && pass "reset-workspace without a terminal refuses and changes nothing (report shows HEAD and ignored files)" "$(echo "$out" | grep -o 'current HEAD:.*')" \
  || fail "reset-workspace refusal without terminal" "$(echo "$out" | tail -3)"
# Answers through a pseudo-terminal (expect).
# Paths and answers go through the environment, so spaces need no quoting in Tcl.
# A timeout ends the run (exit 124) instead of waiting forever.
reset_with() {
  RESET_CMD="$REPO/scripts/up.sh" RESET_ANSWER="$1" expect -c '
    set timeout 600
    spawn $env(RESET_CMD) reset-workspace
    expect {
      timeout { puts "expect: timed out"; exit 124 }
      "Type the repository name" { send "$env(RESET_ANSWER)\r"; exp_continue }
      eof
    }
    catch wait r
    exit [lindex $r 3]' 2>&1
}
out="$(reset_with "wrong/name")"; rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "confirmation did not match; nothing was changed" \
  && [ "$(docker volume ls -q --filter "name=^${VOLUME}-archive-" | sort)" = "$archives_before" ] \
  && [ "$(run_on_volume "git symbolic-ref HEAD" 2>&1)" = "refs/heads/exit-check-orphan" ] \
  && pass "reset-workspace with a wrong repository name refuses and changes nothing" \
  || fail "reset-workspace wrong-name refusal" "$(echo "$out" | tail -3)"
out="$(reset_with "$NWO")"; rc=$?
archive="$(comm -13 <(echo "$archives_before") <(docker volume ls -q --filter "name=^${VOLUME}-archive-" | sort) | head -1)"
if [ "$rc" -eq 0 ] && [ -n "$archive" ]; then
  arch="$(run_on_volume -v "$archive:/archive" "cd /archive && git symbolic-ref HEAD; cat src/exit-check-sentinel; ls exit-check-ignored" 2>&1)"
  [ "$arch" = "$(printf 'refs/heads/exit-check-orphan\nexit-check\nexit-check-ignored')" ] \
    && pass "reset-workspace with confirmation archives the old workspace intact" "$archive: orphan HEAD, untracked and ignored files kept" \
    || fail "archive content" "$arch"
  CID="$(container_id)"
  new="$(in_box "cd /workspace && git rev-parse HEAD && git status --porcelain --ignored | grep -v '^!! node_modules' | wc -l | tr -d ' '")"
  [ "$new" = "$(printf '%s\n0' "$(git -C "$REPO" rev-parse origin/main)")" ] \
    && pass "the new workspace is a fresh clone of origin/main" "$(echo "$new" | head -1 | cut -c1-12), clean" \
    || fail "new workspace after reset" "$new"
  echo "NOTE  reset-workspace archived the project's workspace to $archive (kept on purpose; remove it with: docker volume rm $archive)"
else
  fail "reset-workspace with confirmation" "rc=$rc: $(echo "$out" | tail -3)"
  # Put the workspace back on main so later checks and normal starts work.
  run_on_volume "git switch -q main && rm -f src/exit-check-sentinel exit-check-ignored" >/dev/null 2>&1
fi
section "Restart through up.sh restores the firewall"
"$REPO/scripts/up.sh" true >/dev/null 2>&1 && CID="$(container_id)"
expect_ok "firewall active after restart via up.sh" "test -f /run/firewall-ok || exit 1; curl -s --max-time 5 https://example.com >/dev/null && exit 1 || echo 'marker present, example.com blocked'"

echo
if [ "$FAILS" -eq 0 ]; then echo "RESULT: all checks passed"; else echo "RESULT: $FAILS check(s) failed"; fi
exit "$FAILS"
