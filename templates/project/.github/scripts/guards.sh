#!/usr/bin/env bash
# The factory's own rules for a pull request (spec section 8). Runs from main's
# definition in the guards workflow (pull_request_target): the PR's commits and
# diff are read as data and never executed. Every value from the event arrives
# in the environment; nothing here is evaluated as code.
#
# Env: GH_TOKEN (read-only), REPO, REPO_OWNER, PR_NUMBER, PR_AUTHOR, BASE_SHA,
#      HEAD_SHA, HEAD_REF, HEAD_REPO. Writes findings to GITHUB_STEP_SUMMARY.
set -euo pipefail

SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
FAILS=0
fail() { FAILS=$((FAILS + 1)); printf -- '- **FAIL** %s\n' "$*" >> "$SUMMARY"; echo "FAIL: $*" >&2; }
note() { printf -- '- %s\n' "$*" >> "$SUMMARY"; }
heading() { printf '\n### %s\n\n' "$*" >> "$SUMMARY"; }

OWNER_LABEL=tests-change-approved
PROTECTED='.factory/ .claude/ .github/ .devcontainer/ scripts/ CLAUDE.md'
TEST_CONFIG='package.json tsconfig.json vite.config.ts vite.config.js vitest.config.ts vitest.config.js tests/acceptance/package.json tests/acceptance/playwright.config.ts'

# --- Inputs: validated before use ---------------------------------------------
[[ "$PR_NUMBER" =~ ^[0-9]+$ ]] || { echo "bad PR number" >&2; exit 1; }
[[ "$BASE_SHA" =~ ^[0-9a-f]{40}$ && "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "bad SHA" >&2; exit 1; }

printf '## Factory guards for #%s\n' "$PR_NUMBER" >> "$SUMMARY"

if [ "$HEAD_REPO" != "$REPO" ]; then
  fail "the PR comes from another repository; factory PRs come from branches of this one"
  exit 1
fi

# The PR head as data: fetched, never checked out.
git fetch -q --no-tags origin "+refs/pull/$PR_NUMBER/head:refs/factory/pr-head" "$BASE_SHA"
[ "$(git rev-parse refs/factory/pr-head)" = "$HEAD_SHA" ] \
  || { echo "the fetched head is not the event's head (a newer push will run again)" >&2; exit 1; }
git fetch -q --no-tags origin "+refs/heads/main:refs/factory/main"

COMMITS=()
while IFS= read -r c; do COMMITS+=("$c"); done < <(git rev-list --reverse "$HEAD_SHA" "^$BASE_SHA")

# --- Owner's own PRs ------------------------------------------------------------
# The owner reviews these personally and merges them through the admin bypass;
# the role rules below are for the agents. Any other author gets every rule.
if [ "$PR_AUTHOR" = "$REPO_OWNER" ]; then
  heading "Owner's pull request"
  note "Authored by the owner: role, path and test rules do not apply. ${#COMMITS[@]} commit(s)."
  exit 0
fi

# --- Branch and story -------------------------------------------------------------
heading "Branch"
if [[ "$HEAD_REF" =~ ^(feat|fix|chore|docs|test|refactor)/issue-([0-9]+)-[a-z0-9-]+$ ]]; then
  ISSUE="${BASH_REMATCH[2]}"
  note "story #$ISSUE"
else
  fail "branch name is not \`<type>/issue-<n>-<description>\`"
  ISSUE=
fi

# --- Per commit: messages, trailers and path ownership ---------------------------
allowed() {   # allowed <role> <path>
  case "$1" in
    spec-writer) [[ "$2" == specs/* ]] ;;
    researcher) [[ "$2" == docs/research/* ]] ;;
    test-writer) [[ "$2" == tests/acceptance/* ]] ;;
    implementer)
      case "$2" in
        src/*|public/*|tests/unit/*) return 0 ;;
        */*|.*|CLAUDE.md|README.md) return 1 ;;
        *) return 0 ;;
      esac ;;
    *) return 1 ;;
  esac
}

heading "Commits"
FIRST_IMPL=
TEST_RUNS=0          # runs of consecutive commits changing tests/acceptance/ after the first implementer commit
in_run=
for i in "${!COMMITS[@]}"; do
  c="${COMMITS[$i]}"
  short="${c:0:12}"
  parents=($(git rev-list --parents -n 1 "$c")); parents=("${parents[@]:1}")
  if [ "${#parents[@]}" -gt 1 ]; then
    # A merge passes only as a clean merge of main: second parent on main, tree as git would make it.
    if [ "${#parents[@]}" -ne 2 ]; then fail "$short: an octopus merge"; continue; fi
    if ! git merge-base --is-ancestor "${parents[1]}" refs/factory/main; then
      fail "$short: a merge of something other than main"
    elif [ "$(git merge-tree --write-tree "${parents[0]}" "${parents[1]}" 2>/dev/null | head -1)" != "$(git rev-parse "$c^{tree}")" ]; then
      fail "$short: a merge with changes of its own (not a clean merge of main)"
    fi
    continue
  fi

  subject="$(git log -1 --format=%s "$c")"
  [[ "$subject" =~ ^(feat|fix|docs|chore|test|refactor)(\([a-z0-9-]+\))?!?:\ .+ ]] \
    || fail "$short: message is not Conventional Commits"

  role="$(git log -1 --format='%(trailers:key=Factory-Role,valueonly,separator=)' "$c")"
  files=()
  while IFS= read -r -d '' f; do files+=("$f"); done < <(git diff-tree --no-commit-id --name-only -r -z "$c")

  spec_only=1
  for f in ${files[@]+"${files[@]}"}; do
    [[ "$f" == specs/* || "$f" == docs/research/* ]] || spec_only=
  done
  if [ -z "$role" ]; then
    # Older factory versions wrote spec commits' trailer in a separate paragraph (run.md section 4).
    [ -n "$spec_only" ] && [ "${#files[@]}" -gt 0 ] || fail "$short: no parsed Factory-Role trailer"
  else
    for f in ${files[@]+"${files[@]}"}; do
      allowed "$role" "$f" || fail "$short ($role): \`$f\` is outside the role's paths"
    done
  fi

  [ "$role" = implementer ] && [ -z "$FIRST_IMPL" ] && FIRST_IMPL="$i"
  touches_tests=
  for f in ${files[@]+"${files[@]}"}; do [[ "$f" == tests/acceptance/* ]] && touches_tests=1; done
  if [ -n "$FIRST_IMPL" ] && [ "$i" -gt "$FIRST_IMPL" ] && [ -n "$touches_tests" ]; then
    [ -z "$in_run" ] && TEST_RUNS=$((TEST_RUNS + 1))
    in_run=1
  else
    in_run=
  fi
done
note "${#COMMITS[@]} commit(s) checked"

# --- Factory definitions -------------------------------------------------------------
heading "Factory definitions"
changed=()
while IFS= read -r -d '' f; do changed+=("$f"); done < <(git diff --name-only -z "$BASE_SHA...$HEAD_SHA")
hit=
for f in ${changed[@]+"${changed[@]}"}; do
  for p in $PROTECTED; do
    case "$p" in
      */) [[ "$f" == "$p"* ]] && { fail "\`$f\` is a factory definition"; hit=1; } ;;
      *) [[ "$f" == "$p" ]] && { fail "\`$f\` is a factory definition"; hit=1; } ;;
    esac
  done
done
[ -n "$hit" ] || note "none changed"

# --- Acceptance tests --------------------------------------------------------------
heading "Acceptance tests"
if [ -z "$FIRST_IMPL" ]; then
  note "no implementer commit yet: the test set is not approved yet"
else
  approvals=0
  if [ -n "$ISSUE" ]; then
    approvals="$(gh api --paginate "repos/$REPO/issues/$ISSUE/events" \
      --jq ".[] | select(.event == \"labeled\" and .label.name == \"$OWNER_LABEL\" and .actor.login == \"$REPO_OWNER\") | .id" | grep -c . || true)"
  fi
  if [ "$TEST_RUNS" -gt "$approvals" ]; then
    fail "$TEST_RUNS change(s) to tests/acceptance/ after the tests were approved, $approvals \`$OWNER_LABEL\` label(s) added by the owner"
  else
    note "$TEST_RUNS change(s) after approval, $approvals owner approval(s)"
  fi
fi
existing=()
while IFS= read -r line; do existing+=("$line"); done < <(git diff --name-status "$BASE_SHA...$HEAD_SHA" -- tests/acceptance | awk '$1 != "A" {print}')
if [ "${#existing[@]}" -gt 0 ]; then
  note "existing test files changed or removed (for \"Where to look\"):"
  for line in "${existing[@]}"; do note "  \`$line\`"; done
fi

# --- Test configuration (listed, never failed: decision 7) ----------------------------
heading "Test configuration"
cfg=
for f in ${changed[@]+"${changed[@]}"}; do
  for p in $TEST_CONFIG; do [ "$f" = "$p" ] && { note "changed: \`$f\`"; cfg=1; }; done
done
[ -n "$cfg" ] || note "unchanged"

printf '\n**Result:** %s\n' "$([ "$FAILS" -eq 0 ] && echo "all guards pass" || echo "$FAILS failure(s)")" >> "$SUMMARY"
[ "$FAILS" -eq 0 ]
