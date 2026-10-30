# Step 4 plan: Gates, preview and human-only merge

Status: draft 2, for the owner's review (draft 1 reviewed by a second model; findings in section 12)
Spec: `specs/factory-v1-spec.md` revision 8, section 10, step 4
Date: 2026-10-30

## TL;DR

- **What gets built:** a separate GitHub identity for the agents (a GitHub App), a ruleset that lets no agent change reach `main` without your approval as code owner, GitHub Actions back on with deterministic gates, and a preview deployment on Vercel of every pull request marked ready.
- **Exit (spec section 10):** a PR that breaks any gate cannot be merged, every PR marked ready gets a preview link, and the agent identity cannot merge a PR without your approval.
- **Main choices:** a GitHub App rather than a machine user, because the App gets only the permissions it is given and one-hour tokens; gates that check the factory's rules run from `main`'s definitions, so a PR cannot edit its own gate; the preview is deployed by a pipeline job that never runs the PR's code, so the Vercel token cannot leak to an agent.
- **Where I need you:** approve this plan; create the GitHub App and the Vercel token by following exact steps (both are owner-only); add the secrets yourself so I never see them; merge the PRs; run one story; approve and merge its PR.
- **Most likely reason this slips:** the one-hour App token must be refreshed while a session runs, and that helper is new. Second: GitHub behaviours that the documentation does not settle and must be tested first (section 9).

## 1. Research basis

Checked from primary documentation on 2026-10-30. The references are at the end.

- **A machine user** on a personal repository is a collaborator with every collaborator right (merge, labels, reviews), cannot use a fine-grained token on a repository it does not own, and uses up the one free machine account the terms allow.
- **A GitHub App** can be registered under a personal account, gets only the permissions it is granted, and authenticates with installation tokens that expire after one hour and can be narrowed to one repository and fewer permissions when minted. Its actions are attributed to the App (`<name>[bot]`).
- **Rulesets** are available on public repositories with GitHub Free, including required reviews from code owners, required status checks with an expected source app, and bypass actors. **Push rulesets** (file path restrictions) and **"require workflows to pass"** are not available on a personal account's public repository. A pull request's author cannot approve it.
- **`pull_request` workflows** run the PR's version of the workflow and its scripts. **`pull_request_target`** runs `main`'s version, with a token that can write and with secrets; `GITHUB_SHA` is the base branch's commit. GitHub blocks `pull_request_target` on public repositories by default from 2 December 2026; a policy can allow it for a named workflow file.
- **Required checks:** a skipped job reports success; a workflow skipped by a path filter leaves the check pending.
- **Labels:** GitHub permissions are not per label. The issue's event history records who added a label (`labeled` event, `actor`). The Issues permission also allows renaming labels and editing other users' issue bodies and comments.
- **Environments** with deployment branch policies are available for public repositories on GitHub Free.
- **Vercel Hobby:** for non-commercial personal use. Through the Git integration only the account owner's commits deploy. A deployment made with the owner's token from a pipeline is the owner's. `vercel deploy --prebuilt` deploys a Build Output directory, which can contain serverless functions and routing, not only static files.

## 2. Decisions

Technical choices I made, with the reason. Each one can be overruled.

| # | Decision | Reason |
|---|---|---|
| 1 | **The agent identity is one GitHub App** named `nvipero-factory-orchestrator` (shown as `nvipero-factory-orchestrator[bot]`; owner decision, 2026-10-30), registered under your account and installed only on project repositories. Permissions: Contents, Issues and Pull requests read and write; Metadata read. No Workflows, no Administration, no Checks, no Commit statuses | Least privilege by construction. A machine user cannot be limited below collaborator rights, needs a classic token for a repository it does not own, and uses up the only free machine account |
| 2 | **The App's private key never enters the container.** It is stored in 1Password. `up.sh` signs a JWT on the host with `openssl` (issued-at 60 seconds in the past, against clock skew) and mints an installation token for this one repository | The same separation as step 1: the container gets a short-lived, narrow credential, never the means to make more |
| 3 | **A host-side refresher** started by `up.sh` mints a new token when the current one is older than 45 minutes or expires within 15 (it keeps the mint response's `expires_at`), which also covers waking from sleep. `up.sh` reads the key from 1Password once (one confirmation per session); the refresher keeps it in memory, never on disk. The token is written to a temporary file and renamed into a host directory outside the clone (mode 0700) that is mounted read-only into the container; the directory is mounted, not the file, because a single-file mount keeps the old file after a rename. In the image, a root-owned `gh` wrapper passes the token only in the child process's environment, and a git credential helper answers only for `https://github.com`; both read the file on every call | Sessions last longer than an hour, and an environment variable cannot be updated in a running process. A one-hour token in a read-only file is a smaller exposure than the 30–90-day token it replaces. Spec change: the "never a file on the container's disk" rule becomes "never a long-lived credential" |
| 4 | **No credential in a process's arguments, on the host either.** The key, the JWT and the token reach `openssl` and `curl` through stdin or file descriptors (`curl -K -`, process substitution), never argv | The JWT can mint a token for every installation of the App, and the process list is readable by every process of your user. The step 1 exit check already tests this for the token; it extends to the JWT and the refresh |
| 5 | **Ruleset on `main`:** pull request required, 1 approval, **review from code owners required**, stale approvals dismissed on a new push, the gate checks required with GitHub Actions as their expected source. One bypass actor: the repository admin role (you), in pull request mode, so your own PRs (factory updates) can merge without a second reviewer but never by direct push. `.github/CODEOWNERS` names only you, for every path | Code owner review makes your approval the only one that counts. The App is not an admin, so it cannot bypass. Without the bypass you could not merge your own PRs, because an author cannot approve their own PR. Pinning the source stops a check of the same name from another source from satisfying the rule |
| 6 | **The factory's own rules are checked by a `guards` workflow on `pull_request_target`,** which runs `main`'s definition. It takes the head from `github.event.pull_request.head.sha`, fetches `pull/<n>/head` without checking it out, and reads commits and diff as data, never executing them. Token read-only, no secrets. No `paths`, `paths-ignore` or `if:` on the job, so the check never stays pending or is skipped. **Every value from the event (branch name, PR body, commit messages, trailers, labels) reaches the script only through `env:`, never through `${{ }}` in a `run:` block or `eval`; issue number and branch name are checked against a pattern first** | A PR cannot weaken the gate that judges it, and agent-written text cannot run as code in it. GitHub's default block on 2 December 2026 is lifted for `guards.yml` only, by a policy naming that file. Fallback if a personal account cannot set that policy: `guards` runs on `workflow_run` after a no-op `pull_request` workflow, the same pattern as the preview |
| 7 | **Tests run in a `tests` workflow on `pull_request`,** with a read-only token, no secrets and `persist-credentials: false`: type check, lint, unit tests, build, Playwright acceptance tests, and a dependency review. **The workflow runs fixed commands** (`npx tsc --noEmit`, `npx vitest run`, `npx playwright test` in `tests/acceptance/`), not `npm test` | Tests must run the PR's code. The App cannot change workflow files (no Workflows permission, verified in the exit check), so the PR cannot change which commands run. Fixed commands remove the need for a separate test-tamper gate: changes to the Vitest or Playwright configuration are listed in the guard's check summary for the code reviewer and "Where to look" instead (a simpler route found in review) |
| 8 | **The preview is deployed in two jobs.** A `preview-build` job on `pull_request` (types `ready_for_review`, `synchronize`, `reopened`, skipped while the PR is a draft) builds the static app without any secret and uploads `dist/`. The orchestrator keeps the PR a draft until the code reviewer approves and turns it back into a draft for a change request, so only a PR ready for you is deployed: the agents do not need the preview (owner, 2026-10-30). A `preview-deploy` job, started by `workflow_run` from `main`'s definition, runs only if the build succeeded, came from a `pull_request` event and from this repository. In environment `preview` (deployment branches: `main` only), it creates an empty Build Output directory, writes its own `config.json` (`{"version": 3}`), copies only regular files from the artifact's `dist/` into `static/` with a size limit, takes the Vercel project from environment variables, and deploys with a pinned `vercel` CLI and `vercel deploy --prebuilt`; the token is in that step's `env:` only. The deploy job comments the link on the PR. `preview-build` is not a required check | Your observation: deploying is the pipeline's job, not the agents'. The token is yours, so the Hobby rule on commit authors does not apply. The artifact is written by PR code, so the deploy job treats it as untrusted data: no functions, routes or project settings from it reach Vercel. The Vercel Git integration stays off, so no `vercel.json` decides anything |
| 9 | **Owner-only labels are trusted by who added them.** `spec-approved` and `tests-change-approved` count only if the issue's latest `labeled` event for them has your account as actor. The orchestrator and the guards both check this. A small `label-audit` workflow removes an owner-only label added by anyone else, and fails loudly when a label is created, renamed or deleted by anyone but you | Permissions cannot do this, and the audit is cheap ("trust, but verify"). Renaming is covered because the App's Issues permission allows it |
| 10 | **Trusted input becomes "authored by the owner and not edited by anyone else".** Factory comments are authored by the App, so the run no longer needs the `<!-- factory:` marker. An owner comment or issue body counts only if it was never edited or its last editor is you (GraphQL `userContentEdits`) | Step 3's known limitation (the agents could forge an owner comment) goes away with the separate identity; the edit check closes the remaining route, since the App could edit your text |
| 11 | **Actions settings:** only GitHub-owned actions and those listed by SHA; actions pinned to a full commit SHA (`actions/checkout` v7 or later, `actions/download-artifact` 4.1.8 or later); `GITHUB_TOKEN` read-only by default; Actions may not create or approve pull requests; no repository-level secrets | The narrowest settings that still run the gates. `up.sh` checks them instead of "Actions disabled" |
| 12 | **Static analysis:** CodeQL default setup (free on public repositories) and the dependency review action. Exact tools are confirmed while building, as spec section 8 requires | Both are GitHub's own and need no extra service |

## 3. What changes where

**Factory repository**
- `templates/project/.github/`: `CODEOWNERS`, workflows `guards.yml`, `tests.yml`, `preview-build.yml`, `preview-deploy.yml`, `label-audit.yml`, and the guards' script.
- `templates/project/.devcontainer/`: the `gh` wrapper and git credential helper; the token mount.
- `templates/project/scripts/up.sh`: App token minting and refresher; preflight checks for the ruleset (including exactly one bypass actor, the admin role in pull request mode), code owners, Actions settings, the `pull_request_target` policy and the App installation, replacing "Actions disabled".
- `scripts/setup-github.sh`: the ruleset, Actions settings, the `pull_request_target` policy, environment `preview`.
- `commands/run.md`: trusted input by author and editor; owner labels checked by actor; the CI status read before marking a PR ready; the ready comment says the preview link follows on the PR (the deploy job posts it; the orchestrator does not wait for it).
- Roles commit with their own author name (section 10).
- Spec revision 9, README, exit check.

**Project repositories:** copied from the template as before, through a pilot PR.

## 4. Gates

| Gate | Workflow | What fails it |
|---|---|---|
| Path ownership | guards | A commit touches paths outside the role in its `Factory-Role` trailer, or has no parsed trailer. A merge commit passes only if its second parent is an ancestor of `origin/main` and its tree equals `git merge-tree --write-tree` of its parents (a clean merge with nothing added) |
| Factory definitions | guards | The PR changes `.factory/`, `.claude/`, `.github/`, `.devcontainer/`, `scripts/` or `CLAUDE.md` |
| Acceptance tests | guards | The approved test set is read from the branch, not from the status comment: the test-writer commits before the first implementer commit. A later change under `tests/acceptance/` needs a `tests-change-approved` `labeled` event by you newer than the first implementer commit, one event per later run of test-writer commits. The guard also lists every earlier story's test whose tags or body changed, as a check summary for "Where to look" |
| Test configuration | guards | Never fails; lists changes to the Vitest and Playwright configuration and `package.json` scripts in the check summary (decision 7) |
| Commit messages | guards | A commit message that is not Conventional Commits |
| Types, lint, unit, build, acceptance | tests | Any failure |
| Dependencies | tests | The dependency review action reports a high-severity vulnerability |
| Code scanning | CodeQL | A high-severity alert |

The orchestrator's own checks stay: they stop a run early, and the gates are the barrier that holds even if a run is wrong. The status comment stays the orchestrator's working record; no gate reads it, because the App can edit it.

## 5. Feature-removal stories (owner question, 2026-10-30)

- The spec's acceptance criteria state the absence: "the board shows no Archive button", "tasks stored with the old status still load".
- The test writer removes the tests of the removed behaviour in the tests phase, before the tests are approved. That is its own path, so no label is needed; the coverage review checks that each removed test belongs to the removed behaviour, and the guard's check summary lists the removed tests so the change is in "Where to look".
- After the tests are approved, any further change needs `tests-change-approved`, as for every story.

## 6. Build order and verification

Each piece is tested on the pilot before the next starts.

1. **App and token:** you create the App (exact settings from me), store its key in 1Password and install it on sdlc-pilot. I build the minting and the refresher. Verified: `gh` and `git push` work from the container across two refreshes and after the Mac sleeps past the token's expiry; a refreshed token is visible in the container within seconds through Rancher Desktop's file sharing; the key is not in the container; neither the JWT nor a token appears in the host's process list during a mint; an expired token fails closed; the App token cannot push a change under `.github/workflows/` or create a check run or commit status.
2. **Workflows first, then the ruleset:** the workflows go to `main` before the ruleset requires their checks, since a check that has never run cannot be selected. Then the ruleset and code owners, verified with a test PR from the App: it cannot merge without your approval; a push after your approval dismisses it; your own PR merges through the bypass, and a direct push to `main` is refused; a label added by the App is removed by `label-audit`.
3. **Guards:** first the `pull_request_target` policy for `guards.yml`, proven by a run (or the fallback in decision 6). Then one deliberately broken PR per guard, each blocked with the reason in the check output, plus:
   - a PR whose branch name, commit message and body contain `$(id)`, backticks and `"; curl …`: nothing runs, and the guards judge it normally;
   - a PR that changes the guards' own script: it is judged by `main`'s script;
   - an unclean merge commit: blocked.
4. **Tests and code scanning:** a PR with a failing unit test and one with a failing acceptance test, both blocked.
5. **Preview:** no deploy while the PR is a draft; the link appears on the PR after it is marked ready and again after a push to a ready PR; the deploy job's log shows no PR code ran; the Vercel token is not readable from the build job; an artifact that also contains `functions/` and `.vercel/project.json` deploys only static files to the right project.
6. **Orchestrator and a real story:** a new story run end to end under the App identity; you approve and merge the PR.

## 7. Exit check and evidence

**Scripted (`scripts/exit-check.sh`):**
- The App token in the container expires within an hour and cannot reach any other repository; the key is not in the container; the token file is read-only; neither the JWT nor a token is in any host process's arguments during a mint.
- The App token cannot push a workflow file, create a check run or commit status, or merge a PR without your approval (positive test PRs, cleaned up afterwards, as in step 1).
- The ruleset requires code owner review and the gate checks with GitHub Actions as their source, and has exactly one bypass actor (the admin role, pull request mode); `CODEOWNERS` on `main` names only the owner.
- Actions settings match decision 11; the `pull_request_target` policy exists and names only `guards.yml`; the `guards` and `preview-deploy` workflows on `main` trigger only on `pull_request_target` and `workflow_run`; no workflow has `${{ }}` with event data in a `run:` block.
- The step 1 to 3 checks still pass, with "Actions disabled" replaced.

**From the real run (`docs/verification/step-4.md`):** the broken PRs and their blocked checks, the preview link, the App as the pusher of every factory commit and the author of every factory comment, each commit's author name showing its role, your approval as the only one the merge accepted.

## 8. Spec changes (revision 9)

- Section 2: principle 15, **"Trust, but verify"**: a cheap after-the-fact check is added even when the primary control should be enough (owner decision, 2026-10-30).
- Section 4, credentials: the GitHub App, host-minted one-hour tokens, the read-only token file, no credential in argv on the host (decisions 3 and 4).
- Section 4, labels and trusted input: owner-only labels are trusted by who added them; owner text by author and editor (decisions 9 and 10).
- Section 5: feature-removal stories (section 5 of this plan); `tests-change-approved` covers one change (already in `run.md`).
- Section 8: the gates as built (section 4 of this plan); event data never interpolated into workflow scripts.
- Section 10: step 4's exit as verified.

## 9. Open points tested before they are relied on

- **A `pull_request_target` check as a required status:** the documentation lists `pull_request_target` among events that produce PR checks, so it likely attaches to the head commit; tested in build step 3. Fallback: decision 6's `workflow_run` route.
- **The `pull_request_target` policy on a personal account:** the documentation names enterprise, organisation and repository levels; tested first in build step 3, with the same fallback.
- **Whether a ruleset rule can also stop the App from merging after your approval.** Not required by the exit criterion; the managed deny rule on `gh pr merge` stays either way.
- **The ref an environment's branch policy checks in a `workflow_run` run:** expected `main`; tested in build step 5.

## 10. Known limitations in step 4

- **After you approve,** the App could technically merge; only the deny rule in the container prevents it. Your approval is the decision that matters, so this is accepted.
- **Your own PRs need no second review** (decision 5's bypass). You are the only maintainer, so there is no second reviewer to require.
- **Roles share the App identity.** The container has one token, so the orchestrator and the roles cannot be told apart by GitHub permissions. Only the orchestrator acts on GitHub (comments, labels, PRs), which is why the App carries its name. Each role commits with its own author name (`factory <role>`, e.g. `factory test-writer`) next to the `Factory-Role` trailer, so the commit list shows who wrote what. Neither the author name nor the trailer is authenticated: an agent could forge a test-writer commit, which the acceptance-test guard catches only by order and labels. Separate Apps per role give real separation only once roles run in separate sandboxes: backlog item 9, after the V2 layered sandbox (owner decision, 2026-10-30: one App for now).
- **Tests on `pull_request` run the PR's code.** They are trustworthy because the guards and the missing Workflows permission protect what they run, not on their own.
- **The token refresher depends on `up.sh` running** on your Mac. If it stops, the token expires within an hour and the agents lose GitHub access: failing closed. The key is in the refresher's memory for the session.

## 11. Where I need you, and what can go wrong

- **You:** approve this plan; create the App and install it (about 10 minutes, exact steps from me); create a Vercel project and token and add the token and project ids as the `preview` environment's secrets yourself; merge the factory and pilot PRs; run a story; approve and merge its PR.
- **I do on my own:** everything else, and I report results and deviations.
- **Most likely reasons this slips:**
  - The token refresher: a new moving part between the host and the container.
  - The `pull_request_target` policy and required-check attachment (section 9), which can move the guards to the `workflow_run` route.

## 12. Second-model review of draft 1

All findings were taken in; none was rejected.
- Two blocking by the definition, both missing rules rather than built faults: credentials in the host's process list (decision 4) and event data interpolated into the guards' scripts (decision 6).
- Non-blocking, among others: you could not merge your own PRs (decision 5's bypass); the preview artifact can carry functions and project settings (decision 8); the acceptance-test baseline must not come from the editable status comment (section 4); merge commits could hide changes (section 4); label renames and edited owner text (decisions 9 and 10); the Workflows permission as the control the `tests` workflow relies on, now verified (sections 6 and 7); the test-tamper and gate-change gates replaced by fixed commands in `tests.yml` (decision 7).

## References

- GitHub terms of service (machine accounts): https://docs.github.com/en/site-policy/github-terms/github-terms-of-service
- Personal repository permission levels: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/repository-access-and-collaboration/permission-levels-for-a-personal-account-repository
- Personal access tokens: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
- GitHub App installation tokens: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app
- App permissions: https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app and https://docs.github.com/en/rest/authentication/permissions-required-for-github-apps
- Rulesets: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets and https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets
- Approving with required reviews: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/approving-a-pull-request-with-required-reviews
- Required status checks: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks
- Code owners: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners
- `pull_request_target`: https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target and https://github.blog/changelog/2026-06-18-safer-pull_request_target-defaults-for-github-actions-checkout
- Actions policies: https://docs.github.com/en/actions/concepts/about-actions-policies and https://github.blog/changelog/2026-09-17-workflow-execution-protections-in-github-actions-generally-available/
- Events that trigger workflows: https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows
- `GITHUB_TOKEN`: https://docs.github.com/en/actions/concepts/security/github_token
- Environments: https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments
- Actions settings: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository
- Issue events: https://docs.github.com/en/rest/using-the-rest-api/issue-event-types
- Vercel Hobby: https://vercel.com/docs/plans/hobby; commit authors: https://vercel.com/kb/guide/why-aren-t-commits-triggering-deployments-on-vercel; Build Output API: https://vercel.com/docs/build-output-api/primitives; `vercel deploy`: https://vercel.com/docs/cli/deploy; GitHub Actions with Vercel: https://vercel.com/kb/guide/how-can-i-use-github-actions-with-vercel
