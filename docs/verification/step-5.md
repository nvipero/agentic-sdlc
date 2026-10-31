# Step 5 verification

> **TL;DR:** Step 5 passes. Story [sdlc-pilot #82](https://github.com/nvipero/sdlc-pilot/issues/82) went from the owner's issue to a merge ([sdlc-pilot #83](https://github.com/nvipero/sdlc-pilot/pull/83)) with no human code edits, and every definition-of-done item passes on GitHub's records and the exit check. Seven problems are recorded for the next iteration; the most important are that the question, dispute, test-problem and change-request paths have still not run under the App, and that the network evidence rests on counters, not logs.

## Before the run (2026-10-31)

- Pre-run fixes: factory #8 (20a5e77), copied to the pilot in https://github.com/nvipero/sdlc-pilot/pull/81 (57bc41c). The pilot host clone is on `main` at 57bc41c.

**Network counters**, read as root through `docker exec` (plan decision 6):

| Read at (UTC) | Container started | IPv4 REJECT | IPv6 policy DROP | Note |
|---|---|---|---|---|
| 2026-10-31T09:58:19Z | 2026-10-31T09:57:00Z | 7 pkts / 420 bytes | 0 | after `up.sh`, before the story |
| 2026-10-31T17:17:09Z | 2026-10-31T16:45:16Z | 7 pkts / 420 bytes | 0 | after the merge of #83; the container was started again before the run, and the first container's counters were not read before it stopped |

The 7 rejected packets came before any story work. The firewall's own start-up check accounts for at most 3 (example.com has two IPv4 addresses, plus 1.1.1.1); the rest are unexplained. The first `up.sh` failed because Rancher Desktop was not running; the owner started it and ran `up.sh` again. That does not explain the count: the counters belong to rules the firewall creates on every start, and the container's start time is that of the second attempt. The run is judged by the increase from this baseline.

## The run

Story https://github.com/nvipero/sdlc-pilot/issues/82 "As a user I want to drag and drop tasks from one lane to another", written by the owner.

**Spec phase, run 1 (2026-10-31, 16:45–16:47 UTC):** spec writer `written` (4f188c4, author `factory spec-writer`, trailer `Factory-Role: spec-writer`), no research request and no questions; spec reviewer approve, 0 blocking, 2 non-blocking; ready comment with six assumptions. Status and ready comments by `nvipero-factory-orchestrator`. The spec starts with a TL;DR and traces its problem and why to the context (Users, Purpose, Constraints, Non-goals, Open questions), the glossary and the issue.

**Spec approval:** `spec-approved` added by `nvipero` at 16:49:44 (issue events).

**Implementation phase, run 2 (16:49–17:08 UTC):** test writer 20 tests (6e6d7af), test run 18 failed and 2 passed (AC-5 already true without drag), coverage review approve, 0 blocking (2 non-blocking); implementer (b174128), checks ok, unit 25/25, build ok, acceptance 79/79; draft PR #83; implementation review approve, 0 blocking; GitHub checks pass; PR marked ready, ready comment 17:07:57. Preview deployed for b174128 (environment `pr-preview`, by `github-actions[bot]`). No test problem, dispute, research request or question.

**Merge:** the owner approved and merged #83 at 17:16:00 (merge commit 16b6f8e); #82 closed by the merge. No main merge into the branch was needed.

## Definition of done

| DoD item | Result | Evidence |
|---|---|---|
| A story written by the human reaches a merged PR without the human editing code | PASS | #82 opened by `nvipero`; #83 merged; its three commits are authored and committed by `nvipero-factory-orchestrator[bot]` under the names `factory spec-writer`, `factory test-writer`, `factory implementer`, with `Factory-Role` trailers and a Claude co-author; none by the owner |
| Asked only at defined points; TL;DRs; questions carry only the question | PASS | GitHub: two ready comments (spec, PR) and the status comment, no other comments; no questions were asked. Spec and PR description start with `> **TL;DR:**`. No session-only stops (owner, 2026-10-31) |
| Spec problem and why traceable to the approved context | PASS | `specs/82-drag-drop-tasks-lanes.md` cites context sections Users, Purpose, Constraints, Non-goals, Open questions, the glossary, and the issue |
| All gates ran and were required for merge | PASS | Check runs on b174128: guards, unit-and-build, acceptance, dependency-review, CodeQL, all success, from `github-actions` / `github-advanced-security`. Rule suite 4834332972 of the merge push 16b6f8e by `nvipero`: `pull_request`, `required_status_checks`, `code_scanning`, `non_fast_forward`, `deletion` all pass |
| No agent modified acceptance tests, factory definitions or gates | PASS | Files: `specs/`, `src/`, `tests/acceptance/task-drag-and-drop.spec.ts` (test writer's commit only), `tests/unit/`; the implementer's commit touches no acceptance test (`acceptance tests unchanged` check, `guards` success); no `.factory/`, `.github/`, `.devcontainer/` path |
| No agent merged a pull request | PASS | #83 and #81 merged by `nvipero`; no other merges on 2026-10-31 |
| No access outside the container workspace or allowlisted network | PASS | The exit check's network, mount and visibility sections all pass after the run (below). Counters: 7 rejected IPv4 packets at both readings, 0 IPv6; the value matches the start-up baseline, which points to no rejects during the run, but this container's own start value was not read (problem 6) |
| Observed problems written down | PASS | Below |

## Exit check (2026-10-31, 17:17–17:30 UTC)

108 checks pass, 1 fails. Full output kept locally; excerpt, redacted with `scripts/redact.sh`:

```text
## Factory definitions cannot be modified
## Network allowlist
PASS  https://example.com is blocked — curl: (7) Failed to connect to example.com port 443 after 2 ms: Could not connect to server
PASS  outside DNS resolver is blocked — ;; communications error to 8.8.8.8#53: host unreachable
PASS  host gateway is blocked — curl: (7) Failed to connect to 172.17.0.1 port 80 after 0 ms: Could not connect to server
## Network stays closed when the firewall fails
## Restarts: no automatic restart, firewall on every start
## Visibility: nothing outside the project workspace
PASS  mounts: only workspace volume, 5 read-only overlays, Claude volume — 7 mounts, 5 read-only
## Token on disk
## Step 4: GitHub App token
PASS  the token reaches exactly one repository — nvipero/sdlc-pilot
## Agent token reach (observed behaviour)
PASS  agent token cannot merge a PR without the owner's approval (ruleset) — X Pull request nvipero/sdlc-pilot#84 is not mergeable: the base branch policy prohibits the merge.
## Step 2: factory plugin and roles
## Step 3: implementation roles and the browser
## Protections through the API (owner login)
## Step 4: gates on main
## Image is rebuilt when .devcontainer/ changes
## up.sh fails closed
## Token never in a host process's arguments
PASS  no token, JWT, key or GH_TOKEN= in a host process list during mint, start and session — 74 samples
## Workspace is never deleted automatically
FAIL  reset-workspace refusal without terminal — up.sh: preflight OK: nvipero/sdlc-pilot is PUBLIC, ruleset requires your review and the gates (bypass: admin, PRs only), secret scanning and push protection on, Actions restricted, interaction limit 172 days left
## Restart through up.sh restores the firewall
RESULT: 1 check(s) failed
```

**The one failure is the environment, not the factory.** The check's `up.sh reset-workspace` without a terminal needs the App key from 1Password; the authorization prompt was not answered in time (`[ERROR] authorization timeout`, `REFUSING TO START: cannot read the GitHub App key from 1Password`), so the refusal it tests was never reached. `scripts/up.sh` and `.devcontainer/` in the pilot have not changed since the step 4 exit check (2026-10-30T22:29:36Z), where the same check passed, and the exit check's change since then (cad134e) touches only the merge-refusal pattern. Not run again: it would archive another workspace and test unchanged code. The check archived the workspace to `sdlc-pilot-workspace-archive-20261031T172705Z-5303`, which holds nothing unmerged.

## Problems

| # | When | Class | What | Evidence |
|---|---|---|---|---|
| 1 | Before the run | Idea | The container firewall counts rejected packets but does not log them, so the 7 rejects before the run cannot be explained and the network DoD item rests on counts only. Log rejected connections (destination, time) for after-the-fact review. Owner decision 2026-10-31: not in step 5 (it changes the image mid-run); implement in the v2 host gatekeeper, which sees all traffic anyway. Unconfirmed, from memory: the kernel does not write `LOG` lines from a container's network namespace by default (`net.netfilter.nf_log_all_netns=0`), so logging inside the container would need a VM setting or NFLOG with a log daemon | Baseline table above |
| 2 | Before the run | Idea | The owner wants one always-current deployment of `main` to try the project, not only per-PR previews. This is backlog item 22 (production deployment of `main` through the pipeline): deploy on every merge, after `tests` pass on `main`'s commit, to the project's stable production address, which is a placeholder page now. Owner decision 2026-10-31: not in step 5; the first change after v1 closes, before v2 | Owner request in the step 5 session |
| 3 | Spec phase, run 1 | Friction | The spec reviewer's two non-blocking findings are not visible to the owner anywhere: the status comment lists only blocking findings (`commands/run.md:34`, 246) and the ready comment lists assumptions. The owner approves without knowing what the reviewer noted | Status comment on #82 ("2 non-blocking") |
| 4 | Spec phase, run 1 | Not exercised | The spec writer asked no questions and requested no research, so the question and answer path fixed before the run (https://github.com/nvipero/agentic-sdlc/pull/8) did not run under the App identity | #82 comments |
| 5 | Run 2 | Not exercised | No test problem, dispute, resumed run or owner change request happened; those paths remain untested under the App, as after step 3 | #82 status comment |
| 6 | Before run 1 | Friction | The container was started again between the baseline reading and the run, so its counters restarted and the baseline for the run's container was not read. Reading counters by hand is easy to miss; a reading at every start and stop belongs in `up.sh` if the counters stay the evidence | Network counters table |
| 7 | Exit check | Friction | The exit check asks for 1Password authorization more than once, minutes apart; a missed prompt fails an unrelated check after a timeout | Exit check section |

## Proposed order for the next iteration

My proposal; the owner decides the order.

1. **Deployment of `main`** (problem 2, backlog 22): owner decision, the first change after v1.
2. **Run the untested paths on purpose** (problems 4 and 5): stories designed to cause a question, an owner change request, a test problem and a feature removal. Cheap, and they test code that already exists, before v2 changes the ground under it.
3. **Show the reviewers' non-blocking findings to the owner** (problem 3): a line in the ready comment; a small change to `commands/run.md`.
4. **Network evidence** (problems 1 and 6): logs in the v2 host gatekeeper; until then, `up.sh` could print the counters at start and stop.
5. **One 1Password authorization per exit check** (problem 7).
