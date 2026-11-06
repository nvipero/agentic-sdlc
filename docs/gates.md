# Gates and deployment

## Required checks

Required on every project PR:

- **`guards`** runs `main`'s definition on `pull_request_target` and reads the PR's commits and diff as data, never executing them; event values reach its script only through the environment. It fails on: a commit outside its role's paths or without a parsed `Factory-Role` trailer (spec-only commits excepted); a merge commit that is not a clean merge of `main`; a non-Conventional commit message; a branch not named `<type>/issue-<n>-<description>`; any change to `.factory/`, `.claude/`, `.github/`, `.devcontainer/`, `scripts/` or `CLAUDE.md`; changes to `tests/acceptance/` after the first implementer commit beyond the owner's `tests-change-approved` label events. It lists changed earlier tests and test configuration for "Where to look". The owner's own PRs get only a note.
- **`tests`** runs on `pull_request` with a read-only token and fixed commands (not the project's npm scripts): type check, unit tests, build (`unit-and-build`), and Playwright acceptance tests (`acceptance`).
- **`dependency-review`**: no new dependency with a high-severity vulnerability.
- **CodeQL** (default setup) through the ruleset: no high-severity alert.
- **Secret scanning** with push protection.
- **`label-audit`**: owner-only labels by anyone else are removed.

Test commands cannot be weakened from a PR: the workflow fixes them and the App cannot change workflow files.

## Preview

For a PR that is not a draft, `tests` uploads its build; `preview-deploy` runs `main`'s definition on `workflow_run` after `tests` passes, checks without any secret that guards passed on the same commit, then deploys only the build's static files in environment `preview` with the Vercel token, never running PR code there. One preview per PR at `<owner>-<repo>-pr-<n>.vercel.app`, shown in the PR's deployments panel (environment `pr-preview`, which holds no secrets), replaced on each push and removed when the PR closes (`preview-closed`, `preview-cleanup`). Previews need a Vercel login. The Vercel token is scoped to the one project.

## Production

`tests` also runs on every push to `main` (without dependency review) and uploads the build; `production-deploy` runs `main`'s definition on `workflow_run` after it passes, only for a push to `main`, only if the commit is still `main`'s head, and deploys the build's static files in environment `production` (deployable from `main` only, same token) to `<repo>.vercel.app`. Deploys queue rather than replace each other. After the deploy it checks that the production address serves the new deployment. Production is public. Before the first merge a placeholder holds the production place, because Vercel makes a project's first deployment production.

### Operating production

- **A failed run on `main`:** fix it with a new PR, or re-run the `tests` run with **Re-run all jobs**. **Re-run failed jobs** can leave the run without its build, and `production-deploy` then fails on purpose.
- **Rollback:** a revert PR, through the normal pipeline. For an emergency, **Instant Rollback** in the Vercel dashboard (on Hobby only to the previous production deployment; the first one returns to the placeholder). After a rollback Vercel stops moving production to new deployments, so the next `production-deploy` fails with "is the project rolled back?". Undo it in the dashboard (**Undo Rollback**); the pipeline's project-scoped token cannot.
- **Old deployments:** Vercel's deployment retention removes them (Hobby default: 30 days; the last three and the live one are kept).
