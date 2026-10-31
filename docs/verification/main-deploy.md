# Verification: deployment of `main`

> **TL;DR:** The first merge with the new workflows (sdlc-pilot PR #85) deployed `main` to https://sdlc-pilot.vercel.app on its own: `tests` passed on `main`'s commit, `production-deploy` deployed the build and confirmed through Vercel's API that the production address serves it, and the page is byte-identical to the build. The project-scoped token can deploy to production and read the alias. Two checks wait for the next merge: previews unchanged, and an out-of-date run that does not deploy.

Plan: `docs/plans/main-deploy.md`. Factory PR: https://github.com/nvipero/agentic-sdlc/pull/10. Pilot PR: https://github.com/nvipero/sdlc-pilot/pull/85, merged by the owner 2026-10-31.

## Exit check

| Check | How | Result | Evidence |
|---|---|---|---|
| A merge deploys `main` to production | Observed | PASS | Below |
| Previews unaffected | Observed | Pending: next PR | `preview-deploy` skipped on the push run (41230856871), as intended |
| An out-of-date run does not deploy | Observed | Pending: next merge | Re-run all jobs of `tests` run 41230740166 after the next merge; `production-deploy` must skip with "not main's head" |
| Nothing deploys unless `tests` passed on `main` | By inspection | PASS | `check` job condition on `workflow_run.conclusion == 'success'`, `deploy` `needs: check` |
| Deploys are queued, not dropped | By inspection | PASS | `concurrency: {group: production, queue: max}` on `deploy` |
| Token only in environments | Observed | PASS | Below |

### A merge deploys `main` to production (2026-10-31)

- Push of `f1557a8` (merge of #85): `tests` run 41230740166 `push` success, artifact `main-dist-1` (70 358 bytes).
- `production-deploy` run 41230856859 success: `Production https://sdlc-pilot-gikrbr62t-nvipero1.vercel.app`, `Aliased https://sdlc-pilot.vercel.app`, then `sdlc-pilot.vercel.app serves dpl_8kspmreyauE3Nt2Bp42aUJ88UuSo` (the `live` check through `/v4/aliases`). This answers the plan's open question: the project-scoped token may deploy with `--prod`, and read the deployment and the alias.
- GitHub deployment 7462843302 in environment `production`: `sha f1557a8`, `ref main`, statuses waiting → queued → in_progress → success, `environment_url https://sdlc-pilot.vercel.app`. Its `sha` equals the deployed commit (`main`'s head).
- `https://sdlc-pilot.vercel.app/` serves the app (`<title>Tasks`), not the placeholder; its `index.html` SHA-256 `d64fc10c…bb788` equals the artifact's, and the asset names (`index-CtUrjQFD.js`, `index-BazJGZ52.css`) are the artifact's files.

### Token only in environments

- Repository secrets: 0.
- `preview` and `production`: deployment branch `branch:main`, secrets `VERCEL_ORG_ID VERCEL_PROJECT_ID VERCEL_TOKEN`.
- Pilot `main`'s `.github/` matches the factory template file by file, workflows exactly the seven expected.

## Tests before the PR

- `vercel-preview.sh live` with a stub `curl`: matching deployment passes; a different deployment fails after six tries with "is the project rolled back?"; a bad host fails; two API errors (503) followed by a match pass.
- Artifact and head-check `jq` against the pilot's real runs; the exit check's workflow parser against the new template (expected trigger line).
- `shellcheck -S warning` clean. `actionlint` 1.7.7 rejects only `concurrency.queue`, which is newer than that version (GitHub's workflow-syntax docs list `queue: single|max`).

## Not tested

- A rollback in the Vercel dashboard (the `live` failure path on a real project); not provoked on purpose.
- Three quick merges (queueing), and a failing `tests` on `main`; by inspection only.

## Problems

| # | Class | What |
|---|---|---|
| 1 | Friction | The owner had not kept `orgId` and `projectId` from the step 4 setup; the README's setup deletes `.vercel/project.json` and GitHub never shows a secret's value. Fix: the README tells to store both in 1Password next to the token |
