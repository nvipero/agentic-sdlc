# Step 4 plan: Gates, preview and human-only merge

Status: draft 1, for the owner's review
Spec: `specs/factory-v1-spec.md` revision 8, section 10, step 4
Date: 2026-10-30

## TL;DR

- **What gets built:** a separate GitHub identity for the agents (a GitHub App), a ruleset that lets nothing reach `main` without your approval as code owner, GitHub Actions back on with deterministic gates, and a preview deployment of every pull request on Vercel.
- **Exit (spec section 10):** a PR that breaks any gate cannot be merged, every PR gets a preview link, and the agent identity cannot merge a PR without your approval.
- **Main choices:** a GitHub App rather than a machine user, because the App gets only the permissions it is given and one-hour tokens; gates that check the factory's rules run from `main`'s definitions, so a PR cannot edit its own gate; the preview is deployed by a pipeline job that never runs the PR's code, so the Vercel token cannot leak to an agent.
- **Where I need you:** approve this plan; create the GitHub App and the Vercel token by following exact steps (both are owner-only); add the secrets yourself so I never see them; merge the PRs; run one story; approve and merge its PR.
- **Most likely reason this slips:** the one-hour App token must be refreshed while a session runs, and that helper is new. Second: two GitHub behaviours that the documentation does not settle and must be tested first (section 9).

## 1. Research basis

Checked from primary documentation on 2026-10-30. The references are in section 10.

- **A machine user** on a personal repository is a collaborator with every collaborator right (merge, labels, reviews), cannot use a fine-grained token on a repository it does not own, and uses up the one free machine account the terms allow.
- **A GitHub App** can be registered under a personal account, gets only the permissions it is granted, and authenticates with installation tokens that expire after one hour and can be narrowed to one repository and fewer permissions when minted. Its actions are attributed to the App (`<name>[bot]`).
- **Rulesets** are available on public repositories with GitHub Free, including required reviews from code owners and required status checks. **Push rulesets** (file path restrictions) and **"require workflows to pass"** are not available on a personal account's public repository.
- **`pull_request` workflows** run the PR's version of the workflow and its scripts. **`pull_request_target`** runs `main`'s version, with a token that can write and with secrets. GitHub blocks `pull_request_target` on public repositories by default from 2 December 2026; a repository policy can allow it.
- **Labels:** GitHub permissions are not per label. The issue's event history records who added a label (`labeled` event, `actor`).
- **Vercel Hobby:** for non-commercial personal use. Through the Git integration only the account owner's commits deploy, so commits by an App may not deploy at all. A deployment made with the owner's token from a pipeline is the owner's.

## 2. Decisions

Technical choices I made, with the reason. Each one can be overruled.

| # | Decision | Reason |
|---|---|---|
| 1 | **The agent identity is one GitHub App** named `factory-orchestrator` (shown as `factory-orchestrator[bot]`; App names are unique across GitHub, so if it is taken the fallback is `nvipero-factory-orchestrator`), registered under your account and installed only on project repositories. Permissions: Contents, Issues and Pull requests read and write; Metadata read. No Workflows, no Administration, no Checks | Least privilege by construction. A machine user cannot be limited below collaborator rights, needs a classic token for a repository it does not own, and uses up the only free machine account |
| 2 | **The App's private key never enters the container.** It is stored in 1Password. `up.sh` signs a JWT on the host with `openssl` and mints an installation token for this one repository | The same separation as step 1: the container gets a short-lived, narrow credential, never the means to make more |
| 3 | **A host-side refresher** started by `up.sh` mints a new token every 45 minutes, and at once after the Mac wakes if the token is older than that. `up.sh` reads the key from 1Password once (one confirmation per session); the refresher keeps it in memory, never on disk. The token is written to a temporary file and renamed into a host directory that is mounted read-only into the container; the directory is mounted, not the file, because a single-file mount keeps the old file after a rename. In the image, a root-owned `gh` wrapper and a git credential helper read the token from that file on every call | Sessions last longer than an hour, and an environment variable cannot be updated in a running process. A one-hour token in a read-only file is a smaller exposure than the 30–90-day token it replaces. Spec change: the "never a file on the container's disk" rule becomes "never a long-lived credential" |
| 4 | **Ruleset on `main`:** pull request required, 1 approval, **review from code owners required**, stale approvals dismissed on a new push, the gate checks required, no bypass actors. `.github/CODEOWNERS` names only you, for every path | Code owner review makes your approval the only one that counts, even if another identity could approve. With no bypass actor, the App cannot merge before you approve |
| 5 | **The factory's own rules are checked by a `guards` workflow on `pull_request_target`,** which runs `main`'s definition and reads the PR's commits and diff as data, never executing them. Token read-only, no secrets | A PR cannot weaken the gate that judges it. The repository policy allows `pull_request_target` explicitly before GitHub's default block on 2 December 2026 |
| 6 | **Tests run in a `tests` workflow on `pull_request`,** with a read-only token and no secrets: type check, lint, unit tests, build, Playwright acceptance tests, and a dependency review | Tests must run the PR's code. They are not tamper-proof on their own (decision 8 limits that), and they have nothing to leak |
| 7 | **The preview is deployed in two jobs.** A `preview-build` job on `pull_request` builds the static app without any secret and uploads it. A `preview-deploy` job, started by `workflow_run` from `main`'s definition in an environment holding the Vercel token, deploys the uploaded files with `vercel deploy --prebuilt` and comments the link on the PR. It never runs anything from the PR | Your observation: deploying is the pipeline's job, not the agents'. The token is yours, so the Hobby rule on commit authors does not apply, and no agent code runs where the token is |
| 8 | **The guards include a test-tamper check:** a PR may not change the test commands the gates run (`scripts.test` in `package.json`, Vitest and Playwright configuration) without `gate-change`, set by you | Without this, an implementer could make `npm test` pass trivially. "Trust, but verify": the code reviewer reads these files too, and the guard checks them deterministically |
| 9 | **Owner-only labels are trusted by who added them.** `spec-approved`, `tests-change-approved` and `gate-change` count only if the issue's latest `labeled` event for them has your account as actor. The orchestrator and the guards both check this. A small `label-audit` workflow removes an owner-only label added by anyone else | Permissions cannot do this, and the audit is cheap ("trust, but verify") |
| 10 | **Trusted input becomes "authored by the owner".** Factory comments are authored by the App, so the run no longer needs the `<!-- factory:` marker to tell them apart | Step 3's known limitation (the agents could forge an owner comment) goes away with the separate identity |
| 11 | **Actions settings:** only GitHub-owned actions and those listed by SHA; actions pinned to a full commit SHA; `GITHUB_TOKEN` read-only by default; Actions may not create or approve pull requests | The narrowest settings that still run the gates. `up.sh` checks them instead of "Actions disabled" |
| 12 | **Static analysis:** CodeQL default setup (free on public repositories) and the dependency review action. Exact tools are confirmed while building, as spec section 8 requires | Both are GitHub's own and need no extra service |

## 3. What changes where

**Factory repository**
- `templates/project/.github/`: `CODEOWNERS`, workflows `guards.yml`, `tests.yml`, `preview-build.yml`, `preview-deploy.yml`, `label-audit.yml`, and the guards' script.
- `templates/project/.devcontainer/`: the `gh` wrapper and git credential helper; the token mount.
- `templates/project/scripts/up.sh`: App token minting and refresher; preflight checks for the ruleset, code owners, Actions settings and the App installation, replacing "Actions disabled".
- `scripts/setup-github.sh`: the ruleset, Actions settings, environment `preview`.
- `commands/run.md`: trusted input by author; owner labels checked by actor; the CI status read before marking a PR ready; the preview link in the ready comment.
- `vercel.json` joins the protected paths, because it decides which branches deploy.
- Spec revision 9, README, exit check.

**Project repositories:** copied from the template as before, through a pilot PR.

## 4. Gates

| Gate | Workflow | What fails it |
|---|---|---|
| Path ownership | guards | A commit touches paths outside the role in its `Factory-Role` trailer, or has no parsed trailer (merge commits excepted) |
| Factory definitions | guards | The PR changes `.factory/`, `.claude/`, `.github/`, `.devcontainer/`, `scripts/`, `CLAUDE.md` or `vercel.json` |
| Acceptance tests | guards | `tests/acceptance/` changes in a commit after the last test-writer commit approved by review, without `tests-change-approved` added by you. The guard also lists every earlier story's test whose tags or body changed, as a check summary for "Where to look" |
| Test commands | guards | Decision 8 |
| Commit messages | guards | A commit message that is not Conventional Commits |
| Gate change | guards | A change to gate configuration without `gate-change` added by you and a reason in the PR description |
| Types, lint, unit, build, acceptance | tests | Any failure |
| Dependencies | tests | The dependency review action reports a high-severity vulnerability |
| Code scanning | CodeQL | A high-severity alert |

The orchestrator's own checks stay: they stop a run early, and the gates are the barrier that holds even if a run is wrong.

## 5. Feature-removal stories (owner question, 2026-10-30)

- The spec's acceptance criteria state the absence: "the board shows no Archive button", "tasks stored with the old status still load".
- The test writer removes the tests of the removed behaviour in the tests phase, before the tests are approved. That is its own path, so no label is needed; the coverage review checks that each removed test belongs to the removed behaviour, and the guard's check summary lists the removed tests so the change is in "Where to look".
- After the tests are approved, any further change needs `tests-change-approved`, as for every story.

## 6. Build order and verification

Each piece is tested on the pilot before the next starts.

1. **App and token:** you create the App (exact settings from me), store its key in 1Password and install it on sdlc-pilot. I build the minting and the refresher. Verified: `gh` and `git push` work from the container across two refreshes and after the Mac sleeps past the token's expiry; a refreshed token is visible in the container within seconds through Rancher Desktop's file sharing; the key is not in the container; an expired token fails closed.
2. **Ruleset and code owners:** verified with a test PR from the App: it cannot merge without your approval; a push after your approval dismisses it; a label added by the App is removed by `label-audit`.
3. **Guards:** one deliberately broken PR per guard, each blocked, each with the reason in the check output.
4. **Tests and code scanning:** a PR with a failing unit test and one with a failing acceptance test, both blocked.
5. **Preview:** the link appears on the PR; the deploy job's log shows no PR code ran; the Vercel token is not readable from the build job.
6. **Orchestrator and a real story:** a new story run end to end under the App identity; you approve and merge the PR.

## 7. Exit check and evidence

**Scripted (`scripts/exit-check.sh`):**
- The App token in the container expires within an hour and cannot reach any other repository; the key is not in the container; the token file is read-only.
- The ruleset requires code owner review, has no bypass actors, and requires the gate checks; `CODEOWNERS` on `main` names only the owner.
- Actions settings match decision 11; the `guards` and `preview-deploy` workflows on `main` trigger only on `pull_request_target` and `workflow_run`.
- The App cannot merge an approved-less PR (a positive test PR, cleaned up afterwards, as in step 1).
- The step 1 to 3 checks still pass, with "Actions disabled" replaced.

**From the real run (`docs/verification/step-4.md`):** the broken PRs and their blocked checks, the preview link, the App as the pusher of every factory commit and the author of every factory comment, each commit's author name showing its role, your approval as the only one the merge accepted.

## 8. Spec changes (revision 9)

- Section 2: principle 15, **"Trust, but verify"**: a cheap after-the-fact check is added even when the primary control should be enough (owner decision, 2026-10-30).
- Section 4, credentials: the GitHub App, host-minted one-hour tokens, the read-only token file (decision 3).
- Section 4, labels: owner-only labels are trusted by who added them (decision 9).
- Section 5: feature-removal stories (section 5 of this plan); `tests-change-approved` covers one change (already in `run.md`).
- Section 8: the gates as built (section 4 of this plan), and `vercel.json` in the protected paths.
- Section 10: step 4's exit as verified.

## 9. Open points tested before they are relied on

- **A `pull_request_target` check as a required status:** the documentation does not say whether its result attaches to the PR's head commit so that the ruleset sees it. Fallback: the guard posts a commit status to the head commit itself.
- **`vercel deploy --prebuilt` from an uploaded artifact:** the deploy job must ignore any Vercel project settings inside the artifact and deploy only static files to the project named in the environment.
- **Whether a ruleset rule can also stop the App from merging after your approval.** Not required by the exit criterion; the managed deny rule on `gh pr merge` stays either way.

## 10. Known limitations in step 4

- **After you approve,** the App could technically merge; only the deny rule in the container prevents it. Your approval is the decision that matters, so this is accepted.
- **Roles share the App identity.** The container has one token, so the orchestrator and the roles cannot be told apart by GitHub permissions. Only the orchestrator acts on GitHub (comments, labels, PRs), which is why the App carries its name. Each role commits with its own author name (`factory <role>`, e.g. `factory test-writer`) next to the `Factory-Role` trailer, so the commit list shows who wrote what; the trailers and the guards are what the checks rely on, since an author name is not authenticated. Separate Apps per role give real separation only once roles run in separate sandboxes: backlog item 9, after the V2 layered sandbox (owner decision, 2026-10-30: one App for now).
- **Tests on `pull_request` run the PR's code.** They are trustworthy because the guards protect what they run, not on their own.
- **The token refresher depends on `up.sh` running** on your Mac. If it stops, the token expires within an hour and the agents lose GitHub access: failing closed.

## 11. Where I need you, and what can go wrong

- **You:** approve this plan; create the App and install it (about 10 minutes, exact steps from me); create a Vercel project and token and add the token as the `preview` environment secret yourself; merge the factory and pilot PRs; run a story; approve and merge its PR.
- **I do on my own:** everything else, and I report results and deviations.
- **Most likely reasons this slips:**
  - The token refresher: a new moving part between the host and the container.
  - The two open points in section 9, which can change how the guards report.

## References

- GitHub terms of service (machine accounts): https://docs.github.com/en/site-policy/github-terms/github-terms-of-service
- Personal repository permission levels: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/repository-access-and-collaboration/permission-levels-for-a-personal-account-repository
- Personal access tokens: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
- GitHub App installation tokens: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app
- App permissions: https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app
- Rulesets: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets and https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets
- Code owners: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners
- `pull_request_target`: https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target
- Actions settings: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository
- Issue events: https://docs.github.com/en/rest/using-the-rest-api/issue-event-types
- Vercel Hobby: https://vercel.com/docs/plans/hobby; commit authors: https://vercel.com/kb/guide/why-aren-t-commits-triggering-deployments-on-vercel; Git configuration: https://vercel.com/docs/project-configuration/git-configuration
