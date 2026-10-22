#!/usr/bin/env bash
# Step 1 exit check. Runs on the host against a project whose container was
# started with scripts/up.sh. Prints PASS/FAIL lines; raw output may contain
# host details, so redact it (scripts/redact.sh) before publishing.
#
#   scripts/exit-check.sh <path-to-project-clone> <factory-owner/repo>
#
# Side effects, all cleaned up: one branch and one draft PR on the project
# (agent token positive test), a throwaway local branch and worktree, a test
# image, and container restarts. Nothing is merged.
set -uo pipefail

REPO="$(cd "${1:?project clone path}" && pwd)"
FACTORY_NWO="${2:?factory owner/repo}"
FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0

pass() { echo "PASS  $1${2:+ — $2}"; }
fail() { echo "FAIL  $1${2:+ — $2}"; FAILS=$((FAILS + 1)); }
section() { echo; echo "## $1"; }

# Load up.sh functions (read_token, build_image, check_image_label, ...).
# shellcheck source=/dev/null
FACTORY_UP_SOURCE_ONLY=1 source "$REPO/scripts/up.sh"
read_token
set +e   # up.sh enables errexit; checks here must keep going after a failure
NWO="$(cd "$REPO" && gh repo view --json nameWithOwner --jq .nameWithOwner)"
export FACTORY_REPO_URL="https://github.com/$NWO.git"
export FACTORY_DEVCONTAINER_TREE="$(git -C "$REPO" rev-parse HEAD:.devcontainer)"

cid() { docker ps -q --filter "label=devcontainer.local_folder=$REPO"; }
CID="$(cid)"
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
expect_fail "host.lima.internal / host.docker.internal blocked" \
  "for h in host.lima.internal host.docker.internal; do curl -sS --max-time 5 -o /dev/null http://\$h/ 2>&1 && echo REACHED \$h; done; exit 1" "curl: \([0-9]+\)"
for u in https://api.anthropic.com https://api.github.com/zen https://registry.npmjs.org/; do
  expect_ok "$u is reachable" "curl -sS --max-time 10 -o /dev/null -w '%{http_code}' $u"
done

section "Network stays closed when the firewall fails"
docker exec -u root "$CID" sh -c 'printf "api.github.com\nno-such-host.invalid\n" > /tmp/bad-allowlist'
out="$(docker exec -u root -e FACTORY_ALLOWLIST_FILE=/tmp/bad-allowlist "$CID" /usr/local/bin/init-firewall.sh 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then pass "firewall exits non-zero on resolution failure" "$(echo "$out" | tail -1)"; else fail "firewall exits non-zero on resolution failure"; fi
expect_fail "api.github.com unreachable after failed firewall run" "curl -sS --max-time 5 -o /dev/null https://api.github.com/zen" "curl: \([0-9]+\)"
expect_fail "firewall marker removed after failure" "test -f /run/firewall-ok" ""
out="$(docker exec "$CID" bash -c 'FACTORY_ALLOWLIST_FILE=/tmp/bad-allowlist sudo /usr/local/bin/init-firewall.sh' 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then pass "agent cannot pass an allowlist override through sudo" "$(echo "$out" | tail -1)"; else fail "agent cannot pass an allowlist override through sudo" "$out"; fi
expect_ok "network restored by a normal firewall run" "curl -sS --max-time 10 -o /dev/null -w '%{http_code}' https://api.github.com/zen"
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
    "$REPO/scripts/up.sh" true >/dev/null 2>&1 && CID="$(cid)" || { echo "RESULT: aborted, cannot restart container"; exit 1; } ;;
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
expect_fail "merge deny rule active in bypass mode (claude -p)" \
  "cd /workspace && claude -p --dangerously-skip-permissions 'Run exactly this shell command with the Bash tool and report its output verbatim, nothing else: gh pr merge --help. If the tool call is denied, reply with the single word DENIED and the denial reason.' ; exit 1" "DENIED|denied|not allowed|permission"

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
WT="$(mktemp -d)/wt"
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
[ "$rc" -ne 0 ] && echo "$out" | grep -q "expected '$NEW_TREE'" && pass "up.sh refuses a container whose image tree does not match" "$(echo "$out" | tail -1)" \
  || fail "label mismatch refusal" "$out"
git -C "$REPO" worktree remove --force "$WT"; git -C "$REPO" branch -q -D exit-check-rebuild
docker rmi -f factory-exit-check-rebuild:latest >/dev/null 2>&1

section "up.sh fails closed"
out="$(FACTORY_EXPECTED_VISIBILITY=PRIVATE "$REPO/scripts/up.sh" true 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "REFUSING TO START: visibility" && pass "preflight refuses on unexpected visibility" "$(echo "$out" | grep REFUSING)" \
  || fail "preflight refusal" "$out"
[ -z "$(cid)" ] && pass "no container running after refusal" || fail "container running after refusal"
out="$( (FACTORY_GH_TOKEN=""; export FACTORY_GH_TOKEN; NWO="$NWO"; start_container) 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "REFUSING TO START: devcontainer up failed" && pass "up.sh aborts when postStartCommand fails" "$(echo "$out" | grep -E 'init-workspace|REFUSING' | tail -2 | tr '\n' ' ')" \
  || fail "postStartCommand failure abort" "$(echo "$out" | tail -3)"
[ -z "$(cid)" ] && pass "no container left running after failed start" || fail "container running after failed start"

section "Restart through up.sh restores the firewall"
"$REPO/scripts/up.sh" true >/dev/null 2>&1 && CID="$(cid)"
expect_ok "firewall active after restart via up.sh" "test -f /run/firewall-ok || exit 1; curl -s --max-time 5 https://example.com >/dev/null && exit 1 || echo 'marker present, example.com blocked'"

echo
if [ "$FAILS" -eq 0 ]; then echo "RESULT: all checks passed"; else echo "RESULT: $FAILS check(s) failed"; fi
exit "$FAILS"
