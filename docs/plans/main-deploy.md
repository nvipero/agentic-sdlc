# Plan: deployment of `main`

Status: approved by the owner on 2026-10-31 (draft 2; draft 1 reviewed by a second model, findings in section 7)
Spec: `specs/factory-v1-spec.md` revision 11, backlog item 22; `docs/verification/step-5.md`, problem 2
Date: 2026-10-31

## TL;DR

> **TL;DR:** Every merge to `main` deploys automatically to the project's stable production address (`sdlc-pilot.vercel.app`, a placeholder page now), but only after `tests` passes again on `main`'s own commit, and only if that commit is still `main`'s newest. It reuses the preview pattern: `tests` also runs on pushes to `main` and uploads the build, and a new `production-deploy` workflow deploys only its static files in a new GitHub environment `production`. Nothing changes for agents or PRs. Production is public, unlike the previews, which need a Vercel login. The first real test is merging the pilot PR that brings it in: that merge deploys itself.

- **Why:** owner decision 2026-10-31: one always-current version to try the project, the first change after v1, before v2.
- **Where I need you:** approve this plan; create the `production` environment and its secrets (one script and three `gh secret set` commands); merge the factory PR and the pilot PR; re-run one old workflow run for the negative test.
- **Most likely reason this slips:** the workflow can only be tested after it is on `main` (`workflow_run` runs `main`'s definition), so each fix costs a pilot merge round, as in step 4. Mitigation: shell parts tested locally with recorded API responses, and a second-model review of the diff before the PR.

## 1. Basis

Checked 2026-10-31 in official documentation:
- **Vercel project-scoped token** "can only read and write resources belonging to that one project" ([access tokens](https://vercel.com/docs/accounts/access-tokens)). A production deployment is a project resource, so the existing token should deploy to production; not stated explicitly, the first deploy confirms it. There is no per-environment scope: **the current preview token can already deploy to production.** What keeps previews out of production is `main`'s fixed workflow definition, not the token.
- **Vercel Instant Rollback:** on Hobby only to the immediately previous production deployment; after a rollback "Vercel turns off auto-assignment of production domains" until it is undone ([Instant Rollback](https://vercel.com/docs/instant-rollback)).
- **Vercel deployment retention:** Hobby default deletes production deployments after 30 days, but always keeps the last 3 ready production deployments and the one with the production alias; deleted ones can be restored for 30 days ([Deployment Retention](https://vercel.com/docs/deployment-retention), updated 2026-09-16).
- **`workflow_run`** runs the default branch's definition, fires regardless of the triggering run's conclusion, and `branches:` filters on the triggering run's branch ([events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run)).
- **`concurrency`:** by default a new pending run cancels the earlier pending one; `queue: max` keeps up to 100 pending in FIFO order, but "ordering is not guaranteed"; it cannot be combined with `cancel-in-progress: true` ([workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency)).
- **Live state:** production placeholder at `sdlc-pilot.vercel.app` answers 200 "Previews only"; preview addresses answer 302 to Vercel login (`docs/verification/step-4.md`), so production will be the project's first public deployment.
- **Step 4 lessons:** the Vercel CLI's `alias`, `list`, `remove` fail with the narrow token; REST works.

Not checked, from community reports only: re-running only failed jobs drops the earlier attempt's artifacts (actions/upload-artifact issue 323). Handled anyway (decision 4).

## 2. Decisions

| # | Decision | Reason |
|---|---|---|
| 1 | **Trigger:** `tests` gets `push: branches: [main]`; `production-deploy.yml` runs on `workflow_run` of `tests` with `branches: [main]`. Both jobs carry the same condition: the run was a `push` on `main` in this repository and succeeded | The agreed shape (problem 2). The `branches` filter keeps PR test runs from starting it at all; the same condition on the deploy job, not only on the check job, because the `production` environment's branch rule cannot tell a PR-triggered `workflow_run` from a push (its ref is always `main`) |
| 2 | **Only the newest `main` is deployed, and none is lost.** The deploy job uses `concurrency: {group: production, queue: max}`. The check job (no environment, no secret) skips cleanly if the commit is no longer `main`'s head; the deploy job checks again right before `vercel deploy` and fails with "superseded by <sha>" if `main` moved | Without `queue: max`, three quick merges can cancel the newest pending deploy and leave production on an old commit with nothing red (review finding 1). The second check covers the rare case where two queued runs start out of order; it fails rather than passes so the environment's deployment record never claims a deploy that did not happen |
| 3 | **On a push, `tests` runs `unit-and-build` and `acceptance`; `dependency-review` only on PRs.** The push build is uploaded as `main-dist` by its own step (`if: github.event_name == 'push'`); the PR upload stays `preview-dist`, now also limited to `pull_request` | Dependency review compares a PR against its base. A separate name keeps a production artifact from ever being called a preview; the existing draft condition would be true on a push, so both steps get an event condition |
| 4 | **A missing `main-dist` fails the check job loudly**, unlike the preview's silent "draft: no preview". README: recover a failed `main` run with "Re-run all jobs", never "Re-run failed jobs" | Re-running only failed jobs can leave the run green without the build (unconfirmed, decision basis above); production must not skip silently |
| 5 | **Deploy like the preview:** the artifact is data; only its regular files are copied into a static-only Build Output, then `vercel deploy --prebuilt --prod`. The ten lines of assembly are copied, not moved into a shared script | `main` is reviewed code, but the same hardening costs nothing. A shared script would change the working preview workflow for no gain (review finding 13) |
| 6 | **After the deploy, production is verified:** `GET /v13/deployments/<url>` through `vercel-preview.sh` (new `aliases` command) must list the production domain, with a few retries over about 30 seconds; otherwise the job fails | Principle 15. Catches the case where a rollback in the dashboard has turned off auto-assignment and new versions silently stop going live. REST, not page content, so no CDN cache issue |
| 7 | **New environment `production`**, deployable from `main` only, with the same three Vercel secrets as `preview`. The job declares `environment: {name: production, url: https://<repo-name>.vercel.app}` | A production record and its own place for the secrets. Assumption: **the same token**; a second one gives no narrower rights, only separate revocation. Assumption: the Vercel project is named after the repository (README convention) and Vercel added no suffix (true for the pilot); written into the README |
| 8 | **No approval step in `production`** | The owner already approved the PR; a second click per merge defeats "always current" |
| 9 | **Old production deployments are removed by Vercel's own retention** (Hobby default: 30 days, last 3 and the aliased one always kept). No pruning code; the setting stays at the default | Owner question 2026-10-31. Rollback on Hobby needs only the previous one, which is always kept |
| 10 | **README:** the placeholder step stays (a new project gets PRs before its first merge) with the text "Not deployed yet"; a "Production" section: address, when a deploy happens, recovering a failed run, rollback (dashboard only; the pipeline's token cannot undo it, and on Hobby the first rollback returns to the placeholder) | A new project without the placeholder would publish its first preview as production (step 4) |
| 11 | **`scripts/exit-check.sh` is updated in the same PR:** the template file list and allowed workflows include `production-deploy.yml`, triggers `tests:pull_request,push`, the `production` environment's branch rule and secrets checked like `preview`'s | Otherwise the next step's exit check fails, and its "secrets only in environment preview" line would be false (review finding 5) |
| 12 | **Spec revision 12:** backlog 22 marked done; section 8 gets a "Production" paragraph next to "Preview" | The spec is the source of truth |
| 13 | **No change to agents, roles, `run.md`, guards or `up.sh`** | Agents cannot modify workflows; `up.sh` checks only repository secrets and Actions settings, which do not change |

## 3. Work

| # | Who | What |
|---|---|---|
| 1 | Me | Branch `feat/main-deploy` in the factory: `tests.yml`, `production-deploy.yml`, `vercel-preview.sh aliases`, `setup-github.sh production-env`, `exit-check.sh`, README, spec revision 12 |
| 2 | Me | Local tests: the head-check and artifact-check `jq` and the `aliases` parsing against recorded API responses (pilot's real runs and deployments); `actionlint` if available, otherwise noted; the exit check's workflow parser against the new template |
| 3 | Me | Second-model review of the diff; fixes in the same PR |
| 4 | You | Merge the factory PR |
| 5 | You | `scripts/setup-github.sh production-env nvipero/sdlc-pilot` and three `gh secret set ... --env production` (values from 1Password) |
| 6 | Me | Pilot PR copying the changed files. Its own preview still runs from `main`'s old definition, so it shows only that the PR does not break `tests` |
| 7 | You | Merge the pilot PR with the admin bypass. This push is the first production deploy |
| 8 | Me | Checks in section 4, the negative one with you |
| 9 | Me | `docs/verification/main-deploy.md`, memory, brain note proposal |

## 4. Exit check

| Check | How | Evidence |
|---|---|---|
| A merge deploys `main` to production | Observed | `tests` on the push succeeded; `production-deploy` succeeded including the alias verification; `sdlc-pilot.vercel.app` answers 200 with the app, not "Previews only", and its asset file names match the `main-dist` artifact; the `production` deployment record's `sha` compared with the deployed commit (it is `main`'s head at trigger time, not necessarily the run's commit) |
| Previews unaffected | Observed | The next agent or probe PR gets its preview as before; `production-deploy` has no run for that PR's `tests` (branch filter); production unchanged while the PR is open |
| An out-of-date run does not deploy (head check) | Observed | After a second merge, you re-run the older `main` run of `tests` with "Re-run all jobs": `production-deploy` skips with "not main's head", production unchanged |
| Nothing deploys unless `tests` passed on `main` | By inspection | The conclusion condition and `needs` in the workflow; not provoked on purpose |
| Deploys are queued, not dropped | By inspection | `queue: max` in the workflow; three quick merges are not provoked on purpose |
| Token only in environments | Observed | Repository secrets empty; `production` and `preview` deploy from `main` only; updated `exit-check.sh` section "Step 4: gates on main" passes (run on its own, not the whole exit check) |

The full exit check is not run: nothing in the container, `up.sh` or the agents' reach changes.

## 5. Known limitations and risks

- **Production is public; previews are not** (Vercel login). The pilot is a client-side task board with no data on the server. Assumption: public is fine for the pilot. If not, production needs Vercel's deployment protection; whether Hobby can protect the production domain is not researched.
- **`guards` does not run again on `main`.** Merges come only through PRs (ruleset), so every commit on `main` passed `guards` as a PR; `tests` runs again, which is the agreed shape.
- **Rollback stops deploys until undone**, now detected by decision 6 as a failed run, not silently.
- **Hobby limit** of 100 deployments a day is far above the pilot's rate.

## 6. Where I need you

- **You:** approve this plan, including two assumptions: the same token in both environments (decision 7), and a public production address (section 5). Then steps 4, 5 and 7, and the re-run in section 4.
- **I do on my own:** everything else in section 3, including fixes found in the review or the first deploy, through the normal factory and pilot PRs.

## As built

- Decision 6: the command is `vercel-preview.sh live`, and it compares `GET /v4/aliases/<host>` (`deploymentId`) with the new deployment's id from `GET /v13/deployments/<url>`. The `/v13` response's `alias` field lists aliases "assigned upon deployment creation" (Vercel API reference), so it could not show a rollback.
- Decision 4: the push build is `main-dist-<run attempt>`, so "Re-run all jobs" does not collide with the earlier attempt's build (upload-artifact refuses a duplicate name; whether a re-run removes the earlier attempt's artifacts is not documented).
- Second-model review of the diff: no blocking findings; seven non-blocking, taken in or recorded in the verification document.

## 7. Second-model review of draft 1

One blocking finding, twelve non-blocking. Checked against GitHub's documentation and the repository before taking them in.
- **Blocking, taken in:** plain `concurrency` cancels the pending run when a third arrives, so production could stay on an old commit with nothing red → `queue: max` (decision 2).
- **Taken in:** the head check also in the check job, and failing rather than passing in the deploy job (2); the deployment record's `sha` is `main`'s head at trigger time (section 4); a missing artifact fails loudly and recovery is "Re-run all jobs" (4); `exit-check.sh` would fail and claim secrets only in `preview` (11); production is public while previews need a login (section 5; draft 1 said both were public, which was wrong); decision 3's reason was wrong and the draft condition is true on a push (3); `branches:` filter and the condition on both jobs (1); rollback undo only in the dashboard (10); post-deploy check through REST, not page content (6); the project-name assumption (7); exit checks marked observed or by inspection (section 4); the shared assembly script dropped (5).
- **Also changed, from the owner's question:** old production deployments are left to Vercel's retention (decision 9; draft 1 wrongly implied they pile up forever).
