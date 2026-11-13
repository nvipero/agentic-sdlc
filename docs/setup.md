# Setup

How to start a project with the factory, keep its factory definitions current and renew its protections.

Run the commands from the factory repository's root.

## Starting a new project

**Requirements on the host:**
- A Docker engine with the `docker` CLI. Tested on Rancher Desktop with dockerd (moby), not its containerd option. Another runtime, such as Docker Desktop, OrbStack or Colima, should work but must first pass `scripts/exit-check.sh`: the firewall needs iptables and ipset inside the container, and the token mount relies on how the runtime shares host files (the container's user must read the owner's 0600 token file, read-only, and see a renamed file within a second).
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
   Before that commit, set `components` in the new repository's `.factory/config.yaml` ([components](architecture.md#components)): the frontend's `host` is the deployment target below. **A project with a Supabase backend:** also uncomment the `db` and `functions` components, and in the new repository run `supabase init` with the image's CLI version and copy in the image's lock:
   ```sh
   npx -y "supabase@$(sed -nE 's/^ARG SUPABASE_VERSION=//p' .devcontainer/Dockerfile)" init
   cp .devcontainer/supabase.lock supabase/supabase.lock
   ```
   `supabase init` writes `supabase/config.toml`, which the implementer may then change, and `supabase/.gitignore`, which stays yours. `supabase/supabase.lock` pins the local stack's service versions for the acceptance tests ([gates](gates.md)) and is yours too: the image holds exactly those services, and the exit check fails when it differs from `.devcontainer/supabase.lock`.
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
   Then the deployment target, the frontend component's `host` in `.factory/config.yaml`: `vercel` or `cloudflare`. Do these steps yourself, so nobody else sees the secrets, and set only the chosen target's secrets: `exit-check.sh` expects exactly those (plus `SUPABASE_ACCESS_TOKEN` in both for a Supabase project, below). When switching targets, delete the other target's secrets from both environments.

   **`vercel`.** Do not connect Vercel's Git integration, and skip its "Onboard your agent" offer: the pipeline deploys, the agents never touch Vercel.
   ```sh
   mkdir -p /tmp/vercel-link && cd /tmp/vercel-link
   npx vercel@64.3.1 login
   npx vercel@64.3.1 project create <repo-name>
   npx vercel@64.3.1 link --yes --project <repo-name> && cat .vercel/project.json   # orgId, projectId: keep both in 1Password
   # Vercel makes a project's first deployment its production one, even when a preview
   # is asked for. A placeholder holds that place until the first merge deploys main.
   mkdir -p .vercel/output/static && printf '{"version":3}\n' > .vercel/output/config.json
   printf '<!doctype html><meta charset="utf-8"><title>Not deployed yet</title><p>Production appears here after the first merge to main.</p>\n' > .vercel/output/static/index.html
   npx vercel@64.3.1 deploy --prebuilt --prod
   npx vercel@64.3.1 logout && cd / && rm -rf /tmp/vercel-link
   ```
   Name the Vercel project exactly like the repository, in lowercase letters, digits and hyphens: the `vercel` target script (`.github/scripts/deploy/vercel.sh`) derives the production address from the repository's name. Create a token at vercel.com/account/settings/tokens, scoped to that project only, and store it in 1Password. Vercel has no narrower scope, so the same token serves both environments. Then:
   ```sh
   cd <factory>                # this repository's root: setup-github.sh is here
   repo=<owner>/<repo-name>
   for env in preview production; do
     scripts/setup-github.sh $env-env $repo
     gh secret set VERCEL_TOKEN --env $env --repo $repo
     gh secret set VERCEL_ORG_ID --env $env --repo $repo
     gh secret set VERCEL_PROJECT_ID --env $env --repo $repo
   done
   ```

   **`cloudflare`.** Do not connect Cloudflare's Git integration (Workers Builds): the pipeline deploys. The Worker is named exactly like the repository, in lowercase letters, digits and hyphens: the `cloudflare` target script (`.github/scripts/deploy/cloudflare.sh`) derives it from the repository's name. Create the Worker under your own login, because creating one needs more than the pipeline's token may do; its placeholder is production until the first merge:
   ```sh
   repo=<repo-name>   # the Worker's name
   mkdir -p /tmp/cf-worker/public && cd /tmp/cf-worker
   printf '<!doctype html><meta charset="utf-8"><title>Not deployed yet</title><p>Production appears here after the first merge to main.</p>\n' > public/index.html
   printf '{"name":"%s","compatibility_date":"2026-10-01","workers_dev":true,"preview_urls":true,"assets":{"directory":"./public"}}\n' "$repo" > wrangler.jsonc
   npx wrangler@4.152.0 login
   npx wrangler@4.152.0 deploy
   npx wrangler@4.152.0 logout && cd / && rm -rf /tmp/cf-worker
   ```
   Then, in the Cloudflare dashboard:
   - Create an account-owned API token with the **Editor** role on that one Worker ([roles and permissions](https://developers.cloudflare.com/workers/authorization/)), and store it and the account ID in 1Password. The same token serves both environments.
   - Put the Worker's Previews behind Cloudflare Access, allowing only your own email, and leave production public ([workers.dev and Access](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/)). The first time, this sets up a Zero Trust organisation.

   Then:
   ```sh
   cd <factory>                # this repository's root: setup-github.sh is here
   repo=<owner>/<repo-name>
   for env in preview production; do
     scripts/setup-github.sh $env-env $repo
     gh secret set CLOUDFLARE_API_TOKEN --env $env --repo $repo
     gh secret set CLOUDFLARE_ACCOUNT_ID --env $env --repo $repo
   done
   ```
   **A project with a Supabase backend** also needs its production and staging Supabase projects: [Supabase projects](#supabase-projects).
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

## Supabase projects

For a project with components on host `supabase`, `production-deploy` deploys them to a production Supabase project, and `preview-deploy` deploys each PR's to a shared staging project, both before the frontend ([gates](gates.md)). The free plan allows two active projects, so these two use them; another Supabase project needs one of them paused or another account. Do these steps yourself before the first merge that has Supabase components on `main`, and before syncing a factory change that adds staging to an existing project: without staging, a Supabase project's previews fail and lose their frontend too.

Do steps 1 to 3 once for production and once for staging (`env=production` and `env=preview` below).

1. In the Supabase dashboard, create the project. Note its reference (the `<ref>` in `https://<ref>.supabase.co`, under **Project Settings → General**) and its publishable key (**Project Settings → API Keys**).
2. Create an access token (**Account → Access Tokens**) scoped to that project only, with these permissions (the CLI's names): `projects_read`, `branching_production_read`, `database_write`, `database_pooling_config_read`, `edge_functions_read`, `edge_functions_write`, `edge_functions_secrets_read`. No database password is needed: the CLI logs in through the token and the shared pooler, because GitHub's runners have no IPv6. Store the token in 1Password.
3. Set the secret and the two variables. The variables are public values that end up in the frontend's bundle; `gh secret set` asks for the token and shows nothing:
   ```sh
   repo=<owner>/<repo-name>
   ref=<project reference>     # from step 1
   key=<publishable key>       # from step 1, sb_publishable_...
   env=production              # or preview, for the staging project
   prefix=VITE_                # or STAGING_, for the staging project
   gh secret set SUPABASE_ACCESS_TOKEN --env "$env" --repo "$repo"
   gh variable set "${prefix}SUPABASE_URL" --repo "$repo" --body "https://$ref.supabase.co"
   gh variable set "${prefix}SUPABASE_PUBLISHABLE_KEY" --repo "$repo" --body "$key"
   ```
4. What the pipeline never sets, before the merge that needs it:
   - **Function secrets** (API keys, OAuth secrets). A deploy fails, naming them, while a secret a function reads by name is missing; for a name the code reads with a default and does not need, set any value. In the project's clone, with your own Supabase login (`login` opens the browser). A command that changes the project needs `--yes` when it cannot ask, for example run through Claude Code's `!`:
     ```sh
     ref=<project reference>     # from step 1
     sb() { npx -y "supabase@$(sed -nE 's/^ARG SUPABASE_VERSION=//p' .devcontainer/Dockerfile)" "$@"; }
     sb login
     sb secrets set --yes --remote="$ref" NAME=value   # one NAME=value per secret the deploy named
     sb secrets list --remote="$ref"
     ```
   - **Vault secrets** that migrations read: in the dashboard's SQL editor, `select vault.create_secret('<value>', '<name>');`.
   - **Auth settings** (site URL, redirect URLs, providers, sign-ups): in the dashboard. `supabase/config.toml` applies only to the local stack. In staging, add the preview addresses as redirect URLs: `https://<owner>-<repo>-pr-*.vercel.app/**` on `vercel`, `https://pr-*-<repo>.<subdomain>.workers.dev/**` on `cloudflare`.
   - **Staging is for test values only.** Previews run every PR's code there before review, so its function secrets are test values, never production's keys, and it holds no real data: every preview wipes it, sign-ups included. Any PR's migrations can read and change its Vault, so whatever you set there is a test value too (whether a reset keeps it is checked in [#60](https://github.com/nvipero/agentic-sdlc/issues/60)'s pilot).
   - A function created by hand in the dashboard is deleted by the next deploy (`--prune`): functions come only from `main`. When `main` has no function left, the CLI deploys and deletes nothing, so the last ones stay until you delete them (`sb functions delete --remote="$ref" <name>`).

**When a Supabase deploy fails**, the job stops before the frontend, and production's frontend (or the PR's preview) stays as it was. For staging, the same cases apply with a re-run of the `preview-deploy` run; a failed reset needs no recovery, because the next preview resets staging again:

- **A check fails** (the build's address, a missing secret): nothing has changed. Set the secret, then **Re-run all jobs** on the `production-deploy` run. For the build's address, fix the variable and re-run all jobs of `main`'s `tests` run instead: the build is made there, and a `production-deploy` re-run would reuse the old one. The same applies to the warning that the build has no Supabase address, once the app uses Supabase.
- **A migration fails:** the migrations before it in the same push are applied; the failed one is rolled back (each file runs in one transaction, except statements PostgreSQL refuses in one, such as `create index concurrently`). Functions are not deployed. A later migration does not get past it, because the failed file runs first again on every deploy. Change the failed file in a PR (it was never applied, so this is safe; the guards ask for `migration-approved`), or add a data fix whose timestamp is between the last applied migration and the failed one. Use `supabase migration repair` only by hand, when the history itself is wrong.
- **Migrations out of order** (a PR merged with an older timestamp than one already applied): `db push` refuses. Rename the file in a PR (`migration-approved`), or push it once by hand with `--include-all`.
- **A function deploy fails:** migrations are applied and some functions may be updated. Re-run the job.
- **The project is paused** (a free project pauses after a week without database activity, staging most likely): restore it in the dashboard, then re-run.
- **Data lost to a migration:** there are no down migrations, and the free plan has no backups ([backups](https://supabase.com/docs/guides/platform/backups): daily backups start with Pro). Before a merge with a risky migration, export the data yourself with `sb db dump --remote="$ref" --data-only -f ~/Downloads/$ref-data.sql` (outside the repository); the pipeline does not, because the dump would be personal data in a workflow artifact.

## Updating a project's factory definitions

A project's `.factory/` is a copy of this repository's `skills/`, `agents/` and `commands/`, plus the template's `.factory/`. After a change here, copy it into the project on a branch, open a PR there, merge it, and pull the project's host clone:

```sh
rsync -a --delete --exclude README.md --exclude config.yaml skills agents commands templates/project/.factory/ ../<repo-name>/.factory/
```

Claude Code loads the plugin when a session starts, so after the PR is merged and the host clone pulled, start a new session (`scripts/up.sh claude`) before the next `/factory:run`.

`README.md` files are left out, because every Markdown file in a plugin's `agents/` or `commands/` loads as an agent or a command. `config.yaml` is left out too: a new project gets it from the template copy, and after that it belongs to the project. Bring template changes to it by hand in the same PR. Changes to `.devcontainer/`, `CLAUDE.md` or `scripts/up.sh` are copied from `templates/project/` the same way. When `.devcontainer/supabase.lock` changes (a new `SUPABASE_VERSION`), a project with Supabase components also copies it to `supabase/supabase.lock` in the same PR, or its stack does not start. `.github/` is copied with `rsync -a --delete templates/project/.github/ ../<repo-name>/.github/`, so a file the template no longer has goes too; `scripts/exit-check.sh` fails on any workflow or script on `main` that the template does not have. A label added to `setup-github.sh labels` reaches the project when you run `scripts/setup-github.sh labels <owner>/<repo-name>` again.

## Using the roles in an existing repository

The `assist` plugin (`plugins/assist/`) brings the roles to a repository that is not a factory project, without the pipeline: `/assist:task <issue, description or plan file>` researches and writes a plan that a reviewer checks before you see it, and after your approval an implementer writes tests first and the code, and a reviewer in its own context checks the diff against the plan. It ends with a diff for you to read and the task branch pushed; it opens a pull request only when you ask. The repository's own `CLAUDE.md`, README, test commands and CI are the contract, and nothing of the factory's is written into it: the approved plan and the run's state live in `~/.assist/<repo>/<slug>.md`, and `/assist:task` with that file resumes an interrupted run.

It runs on the host with your permissions, without the container, guards or gates ([risks](risks.md#assist-plugin)). Use it only in repositories where agent use is agreed.

Install it once at user scope, from the host clone of this repository:

```sh
claude plugin marketplace add ~/Personal/github/agentic-sdlc
claude plugin install assist@agentic-sdlc --scope user
```

Then let sessions in any repository read and write the plan files without a prompt each time (this merges into your user settings and keeps what is there):

```sh
mkdir -p ~/.assist
tmp="$(mktemp)" && jq --arg dir "$HOME/.assist" '.permissions.additionalDirectories = ((.permissions.additionalDirectories // []) + [$dir] | unique)' ~/.claude/settings.json > "$tmp" && mv "$tmp" ~/.claude/settings.json
```

The plugin loads in place from the clone, so it is whatever the clone has checked out: a change takes effect at the next session start (or `/reload-plugins`) after you pull, and switching branches in the clone switches the plugin too. The marketplace is registered by absolute path: if the clone moves, run `claude plugin marketplace remove agentic-sdlc` and the two commands above again.

The implementer edits files and runs tests and git. Auto mode runs that without a prompt per step; accept-edits mode still asks for every test run and commit. Your deny and ask rules still apply to the subagents. In auto mode the session pushes the task branch without asking; the changes reach the default branch only through a pull request you merge. Plugin agents cannot set their own permission mode, hooks or MCP servers.

## Renewing protections

The interaction limit expires after six months. `up.sh` warns 14 days before it expires, and refuses to start once it has. To renew it, run `scripts/setup-github.sh interaction-limit <owner>/<repo>`.
