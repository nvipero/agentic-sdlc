# agentic-sdlc

An agent-driven software factory. A user story travels from a GitHub issue to a merged pull request. Agents specify, test, implement and review it, and the human sets direction, answers questions and accepts the result. The full design is in [specs/factory-v1-spec.md](specs/factory-v1-spec.md).

Status: v1 done (2026-10-31). Step 5, the first full run, took a story from the owner's issue to a merge with no human code edits; problems for the next iteration are in `docs/verification/step-5.md`. `/factory:context` writes the project context, and `/factory:run` takes a story from spec to a pull request ready for your review: spec, your approval, acceptance tests, implementation, code review and the GitHub gates. Agents act as a GitHub App, a PR merges only with your approval, every PR marked ready gets a Vercel preview, and every merge deploys `main` to production.

## What is here

| Path | Contents |
|---|---|
| `templates/project/` | Everything copied into a new project repository |
| `scripts/setup-github.sh` | Sets up GitHub protections, labels and the Projects board (six issue-only views, default view removed) for a repository |
| `scripts/exit-check.sh`, `scripts/redact.sh` | Exit check for steps 1 to 3, and redaction of its output before publishing |
| `skills/`, `agents/`, `commands/` | Role knowledge, role definitions and commands (later steps) |
| `specs/`, `docs/` | Specification, plans and verification evidence |

## How the sandbox works

- **Container:** agents run in a dev container on your machine, started only with the project's `scripts/up.sh`.
- **Workspace:** a clone of the project inside a Docker volume, made with the agents' GitHub App token.
- **Read-only from the host:** `.factory/`, `.claude/`, `.github/`, `.devcontainer/` and `CLAUDE.md` are mounted read-only from your host clone of `main`.
- **Not visible in the container:** your host `.git` and `scripts/up.sh`.
- **Network:** outbound traffic is limited to an HTTPS allowlist (Anthropic, GitHub, npm). The firewall fails closed.
- **Browser for acceptance tests:** Playwright's Chromium is installed in the image at build time, pinned with `PLAYWRIGHT_VERSION` in the Dockerfile, so no browser download passes the firewall. A project's `tests/acceptance/package.json` pins `@playwright/test` to the same version; changing it means changing the Dockerfile, which rebuilds the image.
- **Claude Code policy:** set in `/etc/claude-code/managed-settings.json` inside the image. It disables connectors, artifacts, non-essential traffic and updates, and denies merge commands. Sessions start in bypass mode, and the deny rules still apply.
- **Factory definitions as a plugin:** `.factory/` loads as the Claude Code plugin `factory` from the read-only `/workspace/.factory`, so its commands are `/factory:<name>`. Managed settings allow no other source of skills, agents, hooks or plugins, so an agent cannot load a substitute.
- **Agent identity and token:** agents act on GitHub as the GitHub App `nvipero-factory-orchestrator`. Its private key is a 1Password document that never enters the container. `up.sh` reads it once per start, mints a one-hour installation token for the one repository, and leaves a refresher running on your Mac that mints a new one every 45 minutes and within a minute of waking from sleep. The token is written to `~/.factory-run/<repo-name>/token/`, which is mounted read-only into the container; `gh` (a wrapper) and git read it on every call. No key, JWT or token appears in a process's argument list or the container's environment. `up.sh stop` ends the refresher and removes the token.
- **GitHub protections:** a ruleset on `main` with no bypass actors, an interaction limit of collaborators only, and secret scanning with push protection.
- **GitHub Actions (step 4):** restricted to GitHub-owned actions pinned to a full SHA. The workflow token is read-only and cannot approve pull requests. Every outside contributor's run needs approval, and there are no repository-level secrets. `pull_request_target` is allowed for `guards.yml` only. The agents' App has no Workflows permission, so agents cannot change what runs.
- **Gates (step 4):**
  - `guards` runs `main`'s definition on `pull_request_target` and reads the PR as data. It checks commit messages, role trailers and paths, clean merges of `main`, factory definitions, and acceptance-test changes after approval.
  - `tests` runs fixed commands on `pull_request`: type check, unit tests, build, acceptance tests and dependency review. On a push to `main` it runs them again, without dependency review.
  - `label-audit` removes an owner-only label that anyone else added.
  - `preview-deploy` puts a Vercel preview on every PR marked ready, once `tests` and `guards` pass on its commit. One preview per PR at a stable address (`<owner>-<repo>-pr-<n>.vercel.app`), replaced on each push and removed when the PR closes (`preview-closed`, `preview-cleanup`). It shows in the PR's deployments panel (environment `pr-preview`, which holds no secrets). The build comes from `tests`, without secrets. The deploy runs `main`'s definition in environment `preview` and copies only the build's static files, so no PR code runs where the token is.
  - `production-deploy` deploys `main` to the project's production address (`<repo>.vercel.app`, public) after `tests` passes on `main`'s own commit (see "Production" below).
- **Preflight:** on every start, `up.sh` checks these and refuses to start if any check fails:
  - the repository's visibility
  - an active ruleset without bypass actors
  - the interaction limit
  - secret scanning
  - push protection
  - the Actions settings above
  - the host clone is clean, on `main` and equal to `origin/main`
- **The host clone is never updated automatically.** If it is behind `origin/main`, `up.sh` refuses to start. Review the new commits with `git log -p HEAD..origin/main`, then pull with `git pull --ff-only`.

**Known limitation:** after you approve a pull request, the agents' App could technically merge it; only the deny rule in the container prevents that. Your approval is the decision that matters.

## Conventions

- **Commits:** [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/), `type(scope): description`. Types: `feat`, `fix`, `docs`, `chore`, `test`, `refactor`.
- **Branches:** [Conventional Branch 1.1.0](https://conventionalbranch.org/), `<type>/<description>` in lowercase letters, digits and hyphens. `feat/` and `fix/` are allowed short forms.
- The same conventions apply in project repos, including agents' story branches (spec section 5, "Naming conventions").

## Starting a new project

**Requirements on the host:**
- Rancher Desktop (dockerd)
- the devcontainer CLI
- `gh`, logged in as the repository owner, with the `project` scope
- the 1Password CLI `op`
- `git`, `jq`, `openssl` and `curl`

1. **Create the repository:** create an empty public repository on GitHub and clone it next to this one.
2. **Install the GitHub App on it:** in the App's settings (**Install App**), add the repository to the installation. The App is created once, for all projects: Contents, Issues and Pull requests read and write, Metadata read, nothing else, webhook off, installable only on your account; its private key is the 1Password document `nvipero-factory-orchestrator-key` in the vault `Agent Factory`.
3. **Copy the template and push the first commit:**
   ```sh
   rsync -a templates/project/ ../<repo-name>/
   rsync -a --delete --exclude README.md --exclude config.yaml skills agents commands templates/project/.factory/ ../<repo-name>/.factory/
   cd ../<repo-name> && git add -A && git commit -m "chore: initialize project from factory template" && git push -u origin main
   ```
4. **Apply the GitHub setup from this repo.** Run the ruleset after the first push, because it blocks direct pushes to `main`:
   ```sh
   scripts/setup-github.sh ruleset <owner>/<repo-name>
   scripts/setup-github.sh interaction-limit <owner>/<repo-name>
   scripts/setup-github.sh secret-scanning <owner>/<repo-name>
   scripts/setup-github.sh actions <owner>/<repo-name>
   scripts/setup-github.sh code-scanning <owner>/<repo-name>
   scripts/setup-github.sh labels <owner>/<repo-name>
   scripts/setup-github.sh board <owner>/<repo-name>
   ```
   Then turn on the dependency graph by hand (no API): **Settings → Advanced Security → Dependency graph → Enable**. The dependency review gate needs it, and `up.sh` checks it.
   Then the Vercel preview. Do these steps yourself, so nobody else sees the secrets. Do not connect Vercel's Git integration, and skip its "Onboard your agent" offer: the pipeline deploys, the agents never touch Vercel.
   ```sh
   mkdir -p /tmp/vercel-link && cd /tmp/vercel-link
   npx vercel@64.3.1 login
   npx vercel@64.3.1 project create <repo-name>
   npx vercel@64.3.1 link --yes --project <repo-name> && cat .vercel/project.json   # orgId, projectId
   # Vercel makes a project's first deployment its production one, even when a preview
   # is asked for. A placeholder holds that place until the first merge deploys main.
   mkdir -p .vercel/output/static && printf '{"version":3}\n' > .vercel/output/config.json
   printf '<!doctype html><meta charset="utf-8"><title>Not deployed yet</title><p>Production appears here after the first merge to main.</p>\n' > .vercel/output/static/index.html
   npx vercel@64.3.1 deploy --prebuilt --prod
   npx vercel@64.3.1 logout && cd / && rm -rf /tmp/vercel-link
   ```
   Name the Vercel project exactly like the repository, in lowercase letters, digits and hyphens: `production-deploy` derives the production address from the repository's name. Create a token at vercel.com/account/settings/tokens, scoped to that project only, and store it in 1Password. Vercel has no narrower scope, so the same token serves both environments. Then:
   ```sh
   for env in preview production; do
     scripts/setup-github.sh $env-env <owner>/<repo-name>
     gh secret set VERCEL_TOKEN --env $env --repo <owner>/<repo-name>
     gh secret set VERCEL_ORG_ID --env $env --repo <owner>/<repo-name>
     gh secret set VERCEL_PROJECT_ID --env $env --repo <owner>/<repo-name>
   done
   ```
5. **Finish the board in the GitHub UI.** Open the project, then **⋯ → Workflows**. Neither of these steps has an API:
   - **Auto-add to project:** select the repository, set the filter to `is:issue`, and turn it on. The board shows issues only, because a story is an issue and its PR is linked to it. All six saved views also filter on `is:issue`.
   - **Turn off the workflows that change the Status field:** "Item added to project", "Item closed", "Pull request linked to issue", "Pull request merged" and "Auto-close issue". The factory uses labels as status, so a second status that GitHub changes by itself would be misleading.
   - Keep "Auto-add to project" and "Auto-add sub-issues to project" on.
6. **Start the container:** `cd ../<repo-name> && scripts/up.sh`.
   - The first time, log in to Claude Code inside the container with `claude`, then `/login`. The login is stored in the project's Claude volume.
   - To stop the container, run `scripts/up.sh stop`.
   - **The workspace is never deleted automatically.** If `up.sh` stops because the workspace is incomplete or ambiguous (files without `.git`, or a `.git` whose `HEAD` does not resolve), run `scripts/up.sh reset-workspace`. It works in this order:
     1. Shows the workspace content, read-only: current `HEAD`, local branches, commits on no remote branch, stashes, and uncommitted, untracked and ignored files.
     2. Asks you to type the repository name. A wrong name, or no terminal, changes nothing.
     3. Stops the container.
     4. Copies the workspace to an archive volume `<repo>-workspace-archive-<timestamp>`, and checks paths, modes, owners, symlinks and file contents.
     5. Only then replaces the workspace with a fresh clone.

     Nothing is deleted: the archive stays until you remove it with `docker volume rm`. An archive is complete only if it contains the file `.factory-archive-complete`, which is written after the copy has been checked. An interrupted or failed copy removes its own incomplete archive.

**The factory repository itself** gets the same `ruleset`, `interaction-limit`, `secret-scanning` and `actions` setup. The exit check verifies both repositories.

## Production

Every merge to `main` deploys it to `https://<repo>.vercel.app`, which is public (previews need a Vercel login).

- **When:** `tests` runs again on `main`'s commit; after it passes, `production-deploy` deploys the build in environment `production`. Only `main`'s newest commit deploys, if its tests pass; quick merges queue rather than replace each other. The run then checks that the production address serves the new deployment.
- **A failed run on `main`:** fix it with a new PR, or re-run the `tests` run with **Re-run all jobs**. **Re-run failed jobs** can leave the run without its build, and `production-deploy` then fails on purpose.
- **Rollback:** a revert PR, through the normal pipeline. For an emergency, **Instant Rollback** in the Vercel dashboard (on Hobby only to the previous production deployment; the first one returns to the placeholder). After a rollback Vercel stops moving production to new deployments, so the next `production-deploy` fails with "is the project rolled back?". Undo it in the dashboard (**Undo Rollback**); the pipeline's project-scoped token cannot.
- **Old deployments:** Vercel's deployment retention removes them (Hobby default: 30 days; the last three and the live one are kept).

## Updating a project's factory definitions

A project's `.factory/` is a copy of this repository's `skills/`, `agents/` and `commands/`, plus the template's `.factory/`. After a change here, copy it into the project on a branch, open a PR there, merge it, and pull the project's host clone:

```sh
rsync -a --delete --exclude README.md --exclude config.yaml skills agents commands templates/project/.factory/ ../<repo-name>/.factory/
```

Claude Code loads the plugin when a session starts, so after the PR is merged and the host clone pulled, start a new session (`scripts/up.sh claude`) before the next `/factory:run`.

`README.md` files are left out, because every Markdown file in a plugin's `agents/` or `commands/` loads as an agent or a command. `config.yaml` is left out too: a new project gets it from the template copy, and after that it belongs to the project. Bring template changes to it by hand in the same PR. Changes to `.devcontainer/`, `CLAUDE.md` or `scripts/up.sh` are copied from `templates/project/` the same way.

## Renewing protections

The interaction limit expires after six months. `up.sh` warns 14 days before it expires, and refuses to start once it has. To renew it, run `scripts/setup-github.sh interaction-limit <owner>/<repo>`.
