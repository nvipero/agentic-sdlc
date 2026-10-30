# Step 4 verification

Plan: [docs/plans/step-4.md](../plans/step-4.md), approved 2026-10-30. Filled in build step by build step (plan section 6).

## Build step 1: App and token (2026-10-30)

**Result:** the scripted exit check passes in full (all checks, none failed) against sdlc-pilot main with #41 (App token) and #43 (refresher fix) merged.

| Plan check | Evidence |
|---|---|
| `gh` and `git push` work from the container | `agent token can push a branch`, `can open a draft PR`; the zen check through the `gh` wrapper |
| A refreshed token is visible in the container at once | `a refreshed token is seen in the container at once — within 1 s`, then `gh and git work with the refreshed token` |
| The key is not in the container | `no private key anywhere the agent can read outside the project's dependencies — none`; the 1Password document is read only on the host |
| Neither the JWT nor a token in the host's process list | `no token, JWT, key or GH_TOKEN= in a host process list during mint, start and session — 56 samples` |
| An expired or missing token fails closed | `up.sh aborts when workspace init fails — init-workspace: no GitHub token at /etc/factory/token` |
| The App token cannot push a workflow file | `refusing to allow a GitHub App to create or update workflow` (draft 1 review finding N8: now verified, not only from community sources) |
| The App token cannot create a check run or commit status | both `HTTP 403 Resource not accessible by integration` |
| One repository, one hour | `the token reaches exactly one repository — nvipero/sdlc-pilot`; `token expires within an hour — 59 minutes left` |
| The agents have their own identity | the factory repo push is refused for `nvipero-factory-orchestrator[bot]` |

**Owner-run mint test before the container change:** the token is `ghs_`-prefixed, 390 bytes (longer than the 40 characters installation tokens used to have; nothing depends on the length), file mode 0600 in a 0700 directory, 60 minutes valid, one repository.

**Sleep test (owner, 2026-10-30):** the container stayed up while the Mac slept for more than the token's hour; after waking, `gh` in the container worked. The old fine-grained token (`sdlc-pilot-agents` on GitHub, `sdlc-pilot-github` in 1Password) is no longer read by anything and is revoked.

### Found and fixed while verifying

- **The refresher kept a caller waiting.** It inherited open pipe descriptors from `up.sh`'s caller, so the exit check's `reset-workspace` test, which reads `up.sh`'s output, waited until the refresher ended. Interactive use was not affected. The refresher now closes every descriptor above stderr (factory 577ae9b, sdlc-pilot #43); reproduced before the fix (4 s wait in a minimal case) and gone after it (0 s), and the full exit check then ran through.
- **`up.sh stop` said "stopped" when nothing ran.** It now says there was nothing to stop (sdlc-pilot #41).
- **Rancher Desktop's file sharing** (reverse-sshfs) shows the 0600 token file to the container's `node` user (uid 1000, file owner 501), keeps the mount read-only, and shows a file renamed into place within a second. Tested before relying on it.

### Exit check output (2026-10-30T14:51:17Z), step 4 section

```text
## Step 4: GitHub App token
PASS  the container's token is a GitHub App installation token (ghs_ prefix)
PASS  token expires within an hour — 59 minutes left
PASS  the token mount is read-only and holds only the token — read-only, entries: token
PASS  no private key anywhere the agent can read outside the project's dependencies — none
PASS  the token reaches exactly one repository — nvipero/sdlc-pilot
PASS  a refreshed token is seen in the container at once — within 1 s
PASS  gh and git work with the refreshed token — ed62ecd2119b
PASS  the host refresher runs — pid <pid>
PASS  App token cannot create a commit status — gh: Resource not accessible by integration (HTTP 403)
PASS  App token cannot create a check run — gh: Resource not accessible by integration (HTTP 403)

## Agent token reach (observed behaviour)
PASS  agent token can push a branch — pushed chore/exit-check-1793371889
PASS  agent token can open a draft PR — https://github.com/nvipero/sdlc-pilot/pull/44
PASS  agent token cannot push to main (ruleset, fast-forward commit) — remote: error: GH013: Repository rule violations found for refs/heads/main.
PASS  agent token cannot create a ruleset — gh: Resource not accessible by integration (HTTP 403)
PASS  agent token cannot change interaction limits — gh: Resource not accessible by integration (HTTP 403)
PASS  agent token cannot change repository settings — gh: Resource not accessible by integration (HTTP 403)
PASS  agent token cannot push a workflow file (no Workflows permission) —  ! [remote rejected] 609418d25340 -> chore/exit-check-workflow-1793371898 (refusing to allow a GitHub App to cre…
PASS  agent token cannot push to the factory repo — remote: Permission to nvipero/agentic-sdlc.git denied to nvipero-factory-orchestrator[bot].
PASS  probe branch and PR cleaned up (closed, not merged)

## Token never in a host process's arguments
PASS  no token, JWT, key or GH_TOKEN= in a host process list during mint, start and session — 56 samples

RESULT: all checks passed
```

The other sections (steps 1 to 3: overlays, network, restarts, plugin and roles, browser, protections, image rebuild, fail-closed start, workspace) passed unchanged; with the token now in a file, `credential-like env vars` reads `none` instead of `only GH_TOKEN`.

## Build steps 2 to 4: workflows, ruleset, guards, tests (2026-10-30)

**Result:** every deliberately broken PR is blocked for the right reason, the control PR passes every gate, the App cannot merge without your approval, and an App push after your approval dismisses it. sdlc-pilot #45 (workflows), #46 and #58 (preflight) merged; ruleset and Actions settings applied with `scripts/setup-github.sh`.

**Settings as applied** (`setup-github.sh status nvipero/sdlc-pilot`):

```text
ruleset protect-main: enforcement=active bypass_actors=["RepositoryRole:5:pull_request"] target=["~DEFAULT_BRANCH"] rules=["pull_request","non_fast_forward","deletion","required_status_checks","code_scanning"]
  pull_request: {"dismiss_stale_reviews_on_push":true,"require_code_owner_review":true,"required_approving_review_count":1}
  required checks: ["guards@15368","unit-and-build@15368","acceptance@15368","dependency-review@15368"]
  code scanning: [{"alerts_threshold":"errors","security_alerts_threshold":"high_or_higher","tool":"CodeQL"}]
actions: enabled=true allowed=selected sha_pinning=true
selected actions: github_owned=true verified=false patterns=[]
workflow token: read, can approve PRs: false
fork PR approval: all_external_contributors
policy: factory-guards-pull-request-target (active): workflow_path .github/workflows/guards.yml, allowed_events pull_request_target
repository secrets: 0
```

**Open points from plan section 9, now settled:**
- The `pull_request_target` policy can be set on a personal account's public repository through `POST /repos/{owner}/{repo}/actions/policies`, and `guards` runs under it. The list endpoint omits a policy's conditions and rules; the preflight reads each one by id.
- A `pull_request_target` check attaches to the PR's head commit and can be a required check (`guards@15368` above; the probes' merge state followed it).
- The `code_scanning` rule is accepted on a personal public repository.

**Found while building:**
- Dependency review needs the dependency graph, which was off and has no API switch. The owner turned it on in the UI; the preflight checks it through the SBOM endpoint, and the README says so.
- `gh` opened a pager for every call in `setup-github.sh`; `GH_PAGER=cat` in both scripts.

**Probes** (issue #47, PRs #48–#57, opened by `nvipero-factory-orchestrator[bot]` from the container, all closed without merging):

| PR | Probe | guards | tests | Reason in the guards log |
|---|---|---|---|---|
| #48 | test-writer commit in `src/` | failure | pass | `(test-writer): src/main.tsx is outside the role's paths` |
| #49 | no trailer | failure | pass | `no parsed Factory-Role trailer` |
| #50 | non-conventional message | failure | pass | `message is not Conventional Commits` |
| #51 | `scripts/probe.sh`, and `.github/scripts/guards.sh` replaced by `exit 0` | failure | pass | both paths outside the role and both factory definitions: judged by main's script |
| #52 | acceptance test changed after the first implementer commit | failure | pass | `1 change(s) to tests/acceptance/ after the tests were approved, 0 tests-change-approved label(s) added by the owner` |
| #53 | merge of main with a smuggled change | failure | pass | `a merge with changes of its own (not a clean merge of main)` |
| #54 | `$(id)`, backticks, `"; curl …` and `${{ github.token }}` in branch, message, title, body | failure | pass | `branch name is not <type>/issue-<n>-<description>`; no `uid=` anywhere in the log |
| #55 | failing unit test | pass | unit-and-build failure | — |
| #56 | failing acceptance test | pass | acceptance failure | — |
| #57 | control | pass | pass | — |

CodeQL and dependency review passed on all ten.

**label-audit:** the App added `tests-change-approved` to #47; the audit removed it and failed: `owner-only label 'tests-change-approved' added to #47 by nvipero-factory-orchestrator[bot]; removed`.

**Merge only with your approval (#57):**
- Marked ready by the App: `review=REVIEW_REQUIRED state=BLOCKED`. `gh pr merge 57 --merge` as the App: `the base branch policy prohibits the merge`. Further attempts (the REST merge endpoint, `--admin`) were not run: Claude Code's own classifier on the host refused them as merges without review.
- After your approval: `review=APPROVED state=CLEAN`. Not merged.
- After an App push: `review=REVIEW_REQUIRED state=BLOCKED reviews=["nvipero:DISMISSED"]`.

**Local test before the first run:** `guards.sh` against the merged pilot PRs, with the App as author: #35 passes; #39 fails twice for real reasons, the trailer of 1668c0d the owner accepted by hand, and the acceptance-test rename after approval without `tests-change-approved` (issue #29's events confirm no such label was added; it was done under the label exception later withdrawn).

## Build step 5: preview (2026-10-30)

**Result:** a PR that is not a draft gets one preview at a stable address after `tests` and `guards` pass on its commit; a push replaces it; closing or merging removes it. Drafts and PRs failing guards get none, and the job holding the Vercel token never starts for them. sdlc-pilot #59, #62, #63, #64, #67, #68 merged; probes #61, #66, #70, #71 closed without merging.

**As built** (differs from plan decision 8, after the owner's review and what the runs showed):
- No separate build workflow: `tests` uploads its own build for PRs that are not drafts, and `preview-deploy` runs on `tests`' `workflow_run`. A `check` job without the environment confirms the artifact exists and that guards' latest run on the same commit succeeded; only then does the `deploy` job (environment `preview`, deployment branch `main`) load the token. Owner, 2026-10-30: a gate failing after the preview is deployed would leave a preview of rejected code.
- One preview per PR (owner: previews per push pile up) at `<owner>-<repo>-pr-<n>.vercel.app` (owner: one address to test). Each deploy carries `pr=<n>` as Vercel metadata; the new deployment takes the alias, then the PR's other previews are deleted, and the PR's link comment is edited in place. `preview-closed` (no secrets) and `preview-cleanup` (`workflow_run`, environment `preview`) delete a closed PR's previews.
- Deploy uses the Vercel CLI (pinned 64.3.1); alias and deletion use the REST API through `.github/scripts/vercel-preview.sh`. Decision (owner, 2026-10-30): keep the token scoped to the one project. With that token the CLI's `list`, `remove` and `alias` fail with "Could not retrieve Project Settings", because they look up the account first (403) and only `deploy` and `pull` tolerate that (read from the CLI source); the REST endpoints work with the narrow token. The script deletes only deployments with no target (previews) and this PR's number, never the production placeholder.
- Vercel makes a project's first deployment production even when a preview is asked for, also after the production deployment is deleted. A placeholder production page ("Previews only") holds that place; the README's setup does it before the first preview.

**Evidence:**

| Check | Result |
|---|---|
| Draft PR #61 | no preview-build run, no comment |
| Ready PR, CLI target | first runs deployed to production (fixed: `--target=preview` and the placeholder); later runs `Preview  https://sdlc-pilot-…-nvipero1.vercel.app` |
| Stable address #66 | `alias nvipero-sdlc-pilot-pr-66.vercel.app set`; the comment `Preview: https://nvipero-sdlc-pilot-pr-66.vercel.app (updated to f94d262)`, edited to `39be594` after a push |
| Older preview deleted on push | `dpl_4gC47aVnaGDvBphD85skfEmQqCna DELETED`; its own URL then 404 |
| Login required | the stable address answers 302 to `vercel.com/sso-api` |
| Cleanup on close | first run failed (`line 31: 3: unbound variable`, fixed in #67); after it, `dpl_HoFz47vBabpYREV9uSEpdhvxNDnK DELETED`, stable address 404, production placeholder 200 |
| Preview after tests (#70) | tests done 21:24:20, deploy run created 21:24:23: `check=success deploy=success` |
| Guards failing (#71) | tests passed, guards failed: `check=success deploy=skipped`, no comment |
| Cleanup of #70 and #71 | both `success`; #70's address 404 |

**Found on the way:** a PR opened ready got no preview until its next push (fixed: the `opened` event); `vercel project add` is deprecated (`project create`); the first `preview-deploy` after a fix waited about five minutes in `waiting` with no protection rule set and then ran (not explained; not seen again).
