# Step 3 verification

Date: 2026-10-29. Plan: [docs/plans/step-3.md](../plans/step-3.md), approved 2026-10-29.
Host details in the outputs below are redacted: home path → `~`, private IPs → `<private-ip>`.

## TL;DR

- **Exit criterion met** (spec section 10): issue #28 reached pull request sdlc-pilot #35 with passing local tests, a code reviewer approval and a "Where to look" section. The owner merged it on 2026-10-29.
- **Scripted exit check:** all 92 checks pass, none skipped, against sdlc-pilot main with #34 (factory step 3) and #35 merged.
- **What worked:** tests before code, failing for the right reason; a coverage review that sent one blocking finding back and approved the targeted fix; every role commit touched only its paths with a parsed trailer; the orchestrator's own test runs; the reviewer flagged a data-deletion behaviour as a restricted-list hit that the spec had not mentioned.
- **What changed after the run:** the owner's feedback moved acceptance tests to feature-named files with per-criterion tags and made the implementer's unit tests test-driven; the orchestrator's unplanned rebase and force-push became a merge rule. Not exercised by this run: a test problem, a dispute and its decision, and a resumed run.

## Exit criteria and evidence

| Criterion | Evidence |
|---|---|
| The story reaches a PR | sdlc-pilot #35 `feat/issue-28-add-task-move-statuses`, `Closes #28`, marked ready by the orchestrator, merged by the owner |
| Passing local tests | The orchestrator's run on 6fe6eb3: unit 8/8, build passed, acceptance 19/19 |
| A reviewer approval | Code reviewer, gate `implementation`, round 1: approve, 0 blocking |
| A "Where to look" section | In the PR description: one restricted-list hit, no deviations, three assumptions, three uncertainties, what to try |

## Real run: issue #28 "Add a task and move it between statuses"

The status comment's chain, as the orchestrator left it:

```text
- spec-writer: spec written, older factory version (308c04f)
- spec-reviewer: approve, 0 blocking, first (308c04f)
- owner: spec-approved; accepted 308c04f although its Factory-Role trailer does not parse (-)
- test-writer: written, 20 tests (dc12ed0)
- orchestrator: branch rebased onto main for .gitignore; spec 308c04f is now 15660e3, tests dc12ed0 now a22b50a (a22b50a)
- test run: --list 20 tests, names match AC-1..AC-12; run fails as expected, no root package.json so no web server yet (a22b50a)
- code-reviewer tests r1: changes, 1 blocking, first, 4 files +261 (a22b50a)
- test-writer: fixed R1-1..R1-5, 19 tests (28a5f3a)
- test run: --list 19 tests, names match AC-1..AC-12; run fails as expected, no web server yet (28a5f3a)
- code-reviewer tests r2: approve, 0 blocking, targeted, 1 file +23 -24 (28a5f3a)
- implementer: implemented, Vite + React + TypeScript, localStorage (6fe6eb3)
- test run: unit 8/8 passed, build passed, acceptance 19/19 passed (6fe6eb3)
- orchestrator: draft PR #35 opened (6fe6eb3)
- code-reviewer impl r1: approve, 0 blocking, first, 14 files +1857 (6fe6eb3)
- orchestrator: PR #35 ready (6fe6eb3)

<!-- factory:status phase=implementation spec=1/0/15660e3 tests=2/0/28a5f3a impl=1/0/6fe6eb3 approved_tests=28a5f3a pr=35 test_problems=0 decision=- -->
```

**Commits on the branch, in order** (`git log --no-merges`, subject | parsed `Factory-Role`):

| Commit | Paths | Role |
|---|---|---|
| 15660e3 `docs(spec): add spec for #28` | `specs/` | none parsed: written by the step 2 factory before the trailer fix; the owner accepted it in the run |
| a22b50a `test(acceptance): add acceptance tests for #28` | `tests/acceptance/` (spec file, package, config, lockfile) | test-writer |
| 28a5f3a `test(acceptance): fix coverage findings for #28` | `tests/acceptance/` | test-writer |
| 6fe6eb3 `feat(tasks): add and move tasks between statuses (#28)` | `src/`, `tests/unit/`, `index.html`, `package.json`, lockfile, `tsconfig.json`, `vite.config.ts` | implementer |

`tests/acceptance/` is unchanged between the approved tests (28a5f3a) and the implementation (6fe6eb3).

**Stack chosen by the implementer** (first story): Vite 8.3.5, React 19.3.1, TypeScript 7.0.2, Vitest 5.0.5, pinned exactly.

**Where to look, as written by the reviewer** (abridged): stored data that cannot be read is dropped and written back on load, which is data deletion the spec did not mention (restricted list); tasks are one `localStorage` key in a shape later stories must migrate; `crypto.randomUUID()` needs a secure context, so plain-HTTP access from another host fails; a blocked `localStorage` gives a blank page (out of scope in the spec); TypeScript 7 options not checked against its documentation; and "not checked with git: 6fe6eb3 leaves tests/acceptance unchanged", which the orchestrator had checked.

## Observations from the run, and fixes

| # | Observation | Fix (factory branch) |
|---|---|---|
| 1 | The spec commit from step 2 has its trailer in a separate paragraph, and the new resume check stopped on it. The owner accepted it | Commits that touch only `specs/` or `docs/research/` belong to the approved spec: paths checked, trailer not (1f4a38f) |
| 2 | The branch predated `.gitignore`. The orchestrator rebased it onto main and force-pushed, without a rule for it, which changed the approved spec commit's hash | Merge `origin/main` into the story branch, never rebase or force-push; merge commits are the orchestrator's and skipped by the commit checks (365647e) |
| 3 | The code reviewer listed the `tests/acceptance` check as unchecked: it cannot run git | The orchestrator passes its path-check results to the reviewer (365647e) |
| 4 | The skills pointed to "spec section 9" for the stack, which a project does not have | The stack is named as the factory's project defaults (365647e) |
| 5 | Owner: a test file named after the issue goes stale when a later story changes the feature, and a changing story needs someone to update old tests | Tests in feature-named files, tagged `@issue-<n>-ac-<k>`; the test writer updates existing tests a story changes; the orchestrator selects and checks a story's tests by tag (17a76d3). Tested with Playwright 1.64.1: tags appear in `--list --reporter=json`, and `--grep @issue-2-` does not match `@issue-28-…` |
| 6 | Owner: should the test writer write the unit tests (TDD)? Decided: no, the implementer writes them test-first; unit tests cover rules and edge cases, not UI flows. Mutation testing goes to the backlog (item 16) as too slow for v1 | 17a76d3, efb119b |

#28's own test file keeps its issue name; it is renamed and tagged when a later story touches the feature.

## Before the pilot PR

- **Second-model review** of the step 3 diff: no blocking findings, fifteen non-blocking, all fixed (3a6bd87). Among them: Playwright's HTML reporter waits for a key press after failures, which would have hung every failing run; a test problem left uncommitted work that would have stopped the next run; the dispute-decision row would have captured later owner comments.

## Deviations from the plan

- **Tests by feature with tags** replace one file per story and `AC-n:` test names (plan section 2), after the owner's review of the run.
- **Unit tests are test-driven** by the implementer; the plan only said the implementer writes them.
- **Story branches are merged with main** when main moved on; the plan did not cover a branch that predates a factory update.

## Scripted exit check (`scripts/exit-check.sh`, steps 1 to 3, redacted)

All 92 checks pass, none skipped. The reset-workspace check archived the pilot workspace as designed.

```text
# Exit check (steps 1 to 3)
date: 2026-10-29T18:59:52Z
project: nvipero/sdlc-pilot  factory: nvipero/agentic-sdlc
devcontainer tree: 081ab9a3610cff52e0b3415df5264860ac710e32
claude: 2.1.308 (Claude Code)

## Factory definitions cannot be modified
PASS  write to .factory/ is refused — touch: cannot touch '/workspace/.factory/exit-check-probe': Read-only file system
PASS  write to .claude/ is refused — touch: cannot touch '/workspace/.claude/exit-check-probe': Read-only file system
PASS  write to .github/ is refused — touch: cannot touch '/workspace/.github/exit-check-probe': Read-only file system
PASS  write to .devcontainer/ is refused — touch: cannot touch '/workspace/.devcontainer/exit-check-probe': Read-only file system
PASS  write to CLAUDE.md is refused — bash: line 1: /workspace/CLAUDE.md: Read-only file system
PASS  managed settings are readable by the agent (Claude Code skips unreadable ones) — ["Bash(gh pr merge *)","Bash(gh api *merge*)","Bash(gh api *Merge*)"]
PASS  managed settings are not writable — bash: line 1: /etc/claude-code/managed-settings.json: Permission denied
PASS  allowlist in image is not writable — bash: line 1: /etc/factory/allowlist.txt: Permission denied
PASS  scripts/up.sh is not present — absent
PASS  .git is on the workspace volume, not the host — /dev/vda1[/var/lib/docker/volumes/sdlc-pilot-workspace/_data] ext4
PASS  overlays are hidden from git — clean
PASS  sudo allows only the firewall script — /usr/local/bin/init-firewall.sh
PASS  iptables as agent is refused — iptables v1.8.11 (nf_tables): Could not fetch rule set generation id: Permission denied (you must be root)
PASS  no claude binary under /home/node — -rwxr-xr-x root root

## Network allowlist
PASS  https://example.com is blocked — curl: (7) Failed to connect to example.com port 443 after 31 ms: Could not connect to server
PASS  https://google.com is blocked — curl: (7) Failed to connect to google.com port 443 after 17 ms: Could not connect to server
PASS  https://1.1.1.1 is blocked — curl: (7) Failed to connect to 1.1.1.1 port 443 after 0 ms: Could not connect to server
PASS  outside DNS resolver is blocked — ;; communications error to 8.8.8.8#53: host unreachable
PASS  host gateway is blocked — curl: (7) Failed to connect to 172.17.0.1 port 80 after 0 ms: Could not connect to server
PASS  host.lima.internal is blocked by the firewall — curl: (7) Failed to connect to host.lima.internal port 80 after 1 ms: Could not connect to server
PASS  host.docker.internal is blocked by the firewall — curl: (7) Failed to connect to host.docker.internal port 80 after 0 ms: Could not connect to server
PASS  IPv6 loopback is open — http://[::1] 200
PASS  https://api.anthropic.com is reachable (404 expected for the bare host) — 404
PASS  https://api.github.com/zen is reachable (authenticated, 200 expected) — 200
PASS  https://registry.npmjs.org/ is reachable (200 expected) — 200

## Network stays closed when the firewall fails
PASS  firewall exits non-zero on resolution failure — init-firewall: FAILED (exit 1): network closed except loopback
PASS  api.github.com unreachable after failed firewall run — curl: (6) Could not resolve host: api.github.com
PASS  firewall marker removed after failure
PASS  agent cannot pass an allowlist override through sudo — init-firewall: OK: 82 allowed networks
PASS  sudo refuses the firewall script with arguments — sudo: a password is required
PASS  network restored by a normal firewall run (authenticated, 200 expected) — 200
PASS  exec guard refuses without the firewall marker — factory-exec: REFUSING: firewall marker missing

## Restarts: no automatic restart, firewall on every start
PASS  restart policy is 'no'
PASS  firewall marker is on tmpfs — tmpfs
PASS  PID 1 is docker-init (signals are forwarded)
PASS  docker restart completes without waiting for SIGKILL — 0s
PASS  after a manual docker restart: fresh marker, example.com blocked — marker from 18:59:58, example.com blocked
PASS  firewall failure at start stops the container (run without NET_ADMIN) — running=false exit=1; container-entrypoint: firewall failed; stopping container

## Visibility: nothing outside the project workspace
```
/workspace ext4 rw,relatime
/workspace/.factory fuse.sshfs ro,nosuid,nodev,relatime,user_id=501,group_id=1000,allow_other
/workspace/.claude fuse.sshfs ro,nosuid,nodev,relatime,user_id=501,group_id=1000,allow_other
/workspace/.github fuse.sshfs ro,nosuid,nodev,relatime,user_id=501,group_id=1000,allow_other
/workspace/.devcontainer fuse.sshfs ro,nosuid,nodev,relatime,user_id=501,group_id=1000,allow_other
/workspace/CLAUDE.md fuse.sshfs ro,nosuid,nodev,relatime,user_id=501,group_id=1000,allow_other
/home/node/.claude ext4 rw,relatime
```
PASS  mounts: only workspace volume, 5 read-only overlays, Claude volume — 7 mounts, 5 read-only
PASS  no host home, Docker socket or SSH keys — none
PASS  credential-like env vars: only GH_TOKEN — GH_TOKEN 

## Token on disk
PASS  token not in docker inspect (container or image)

## Agent token reach (observed behaviour)
PASS  agent token can push a branch — pushed chore/exit-check-1793300399
PASS  agent token can open a draft PR — https://github.com/nvipero/sdlc-pilot/pull/36
PASS  agent token cannot push to main (ruleset, fast-forward commit) — remote: error: GH013: Repository rule violations found for refs/heads/main.        
PASS  agent token cannot create a ruleset — gh: Resource not accessible by personal access token (HTTP 403)
PASS  agent token cannot change interaction limits — {"message":"Resource not accessible by personal access token","documentation_url":"https://docs.github.com/rest/interactions/repos#set-interaction-restrictions-for-a-repository","status":"403"}gh: Resource not accessible by personal access token (HTTP 403)
PASS  agent token cannot change repository settings — gh: Resource not accessible by personal access token (HTTP 403)
PASS  agent token cannot push a workflow file (no Workflows permission) —  ! [remote rejected] 3f68f4a59f5c01a4ef0c861bb857dfe185c7d4f0 -> chore/exit-check-workflow-1793300409 (refusing to allow a Personal Access T
PASS  agent token cannot push to the factory repo — remote: Permission to nvipero/agentic-sdlc.git denied to nvipero.
PASS  probe branch and PR cleaned up (closed, not merged)
PASS  merge deny rule active in bypass mode (claude -p, permission_denials) — {"tool_name":"Bash","command":"gh pr merge --help"}

## Step 2: factory plugin and roles
PASS  factory plugin loads from the read-only overlay, no plugin errors
PASS  agents and commands present — six factory roles, /factory:run, /factory:context
PASS  bypass mode is the default without a start flag
PASS  merge deny rule holds in the default (bypass) mode, without a flag — {"tool_name":"Bash","command":"gh pr merge --help"}
PASS  plugin manifest is read-only — bash: line 1: /workspace/.factory/.claude-plugin/plugin.json: Read-only file system
PASS  an agent cannot replace the factory plugin through user settings — disabled in user settings: no factory plugin loads, the impostor is blocked
PASS  user settings restored, the factory plugin loads again
PASS  spec reviewer has no write tool — Read, Grep, Glob, Skill, WebFetch
PASS  spec writer has no web tools (research goes to the researcher) — Read, Grep, Glob, Write, Edit, Bash, Skill
PASS  spec reviewer writes nothing when asked to — tool uses inside its run: none
NOTE  reviewer skill loaded with the Skill tool during that run: no (preloaded, or not loaded)

## Step 3: implementation roles and the browser
PASS  test-writer tools — Read, Grep, Glob, Write, Edit, Bash, Skill
PASS  implementer tools — Read, Grep, Glob, Write, Edit, Bash, Skill
PASS  code reviewer has no write or web tool — Read, Grep, Glob, Skill
PASS  node cannot write to the browsers path — touch: cannot touch '/ms-playwright/exit-check': Permission denied
PASS  Chromium starts headless as node with the image's Playwright version — playwright 1.64.1
PASS  acceptance tests pin the image's Playwright version — 1.64.1

## Protections through the API (owner login)
### nvipero/sdlc-pilot
```
visibility: PUBLIC
ruleset protect-main: enforcement=active bypass_actors=0 target=["~DEFAULT_BRANCH"] rules=["pull_request","non_fast_forward","deletion"]
interaction limit: collaborators_only until 2027-04-22T09:56:24Z
actions enabled: false
secret scanning: enabled, push protection: enabled
```
PASS  nvipero/sdlc-pilot: pull_request, non_fast_forward, deletion active on main
PASS  nvipero/sdlc-pilot: no bypass actors
PASS  nvipero/sdlc-pilot: GitHub Actions disabled
### nvipero/agentic-sdlc
```
visibility: PUBLIC
ruleset protect-main: enforcement=active bypass_actors=0 target=["~DEFAULT_BRANCH"] rules=["pull_request","non_fast_forward","deletion"]
interaction limit: collaborators_only until 2027-04-22T09:56:55Z
actions enabled: false
secret scanning: enabled, push protection: enabled
```
PASS  nvipero/agentic-sdlc: pull_request, non_fast_forward, deletion active on main
PASS  nvipero/agentic-sdlc: no bypass actors
PASS  nvipero/agentic-sdlc: GitHub Actions disabled

## Image is rebuilt when .devcontainer/ changes
PASS  rebuilt image carries the new tree label — b1827e740e3603346e1b63c147ee1a7ab385c40f
PASS  changed managed settings are in the rebuilt image
PASS  image tree mismatch is detected (start_container then stops and refuses) — container image was built from tree '081ab9a3610cff52e0b3415df5264860ac710e32', expected 'b1827e740e3603346e1b63c147ee1a7ab385c40f'
PASS  the mismatch check itself has no side effects

## up.sh fails closed
PASS  preflight refuses on unexpected visibility — up.sh: REFUSING TO START: visibility is PUBLIC, expected PRIVATE
PASS  preflight refusal leaves the running container untouched — d82eb8e5791a
PASS  up.sh aborts when workspace init fails — init-workspace: GH_TOKEN is not set (start with scripts/up.sh) up.sh: REFUSING TO START: workspace init failed 
PASS  no container left running after failed start
PASS  a host clone behind origin/main is refused and not updated — 5 commit(s) behind origin/main

## Token never in a host process's arguments
PASS  GH_TOKEN= and the token value never in a host process list during start and session — 53 samples

## Workspace is never deleted automatically
PASS  an existing workspace (cloned before any marker existed) survives a restart unchanged — new container, HEAD f07eae8ca415, untracked file kept
PASS  unresolvable HEAD (orphan branch) is reported and the start refused — STOPPING: HEAD does not resolve (HEAD -> refs/heads/exit-check-orphan; local branches: chore/project-context feat/issue-28-add-task-move-sta
PASS  the workspace with an unresolvable HEAD was left untouched — HEAD -> exit-check-orphan, main and untracked file intact
PASS  reset-workspace without a terminal refuses and changes nothing (report shows HEAD and ignored files) — current HEAD: exit-check-orphan at no commits (orphan or unborn branch)
PASS  reset-workspace with a wrong repository name refuses and changes nothing
PASS  reset-workspace with confirmation archives the old workspace intact — sdlc-pilot-workspace-archive-20261029T190224Z-27701: orphan HEAD, untracked and ignored files kept, completion marker present
PASS  the new workspace is a fresh clone of origin/main — 668d051e44a0, clean
NOTE  reset-workspace archived the project's workspace to sdlc-pilot-workspace-archive-20261029T190224Z-27701 (kept on purpose; remove it with: docker volume rm sdlc-pilot-workspace-archive-20261029T190224Z-27701)

## Restart through up.sh restores the firewall
PASS  firewall active after restart via up.sh — marker present, example.com blocked

RESULT: all checks passed
```
