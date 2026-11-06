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
   Then the deployment target, named by `deploy.target` in `.factory/config.yaml`. The only target is `vercel`, set up as follows. Do these steps yourself, so nobody else sees the secrets. Do not connect Vercel's Git integration, and skip its "Onboard your agent" offer: the pipeline deploys, the agents never touch Vercel.
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

## Updating a project's factory definitions

A project's `.factory/` is a copy of this repository's `skills/`, `agents/` and `commands/`, plus the template's `.factory/`. After a change here, copy it into the project on a branch, open a PR there, merge it, and pull the project's host clone:

```sh
rsync -a --delete --exclude README.md --exclude config.yaml skills agents commands templates/project/.factory/ ../<repo-name>/.factory/
```

Claude Code loads the plugin when a session starts, so after the PR is merged and the host clone pulled, start a new session (`scripts/up.sh claude`) before the next `/factory:run`.

`README.md` files are left out, because every Markdown file in a plugin's `agents/` or `commands/` loads as an agent or a command. `config.yaml` is left out too: a new project gets it from the template copy, and after that it belongs to the project. Bring template changes to it by hand in the same PR. Changes to `.devcontainer/`, `CLAUDE.md` or `scripts/up.sh` are copied from `templates/project/` the same way. `.github/` is copied with `rsync -a --delete templates/project/.github/ ../<repo-name>/.github/`, so a file the template no longer has goes too; `scripts/exit-check.sh` fails on any workflow or script on `main` that the template does not have.

## Renewing protections

The interaction limit expires after six months. `up.sh` warns 14 days before it expires, and refuses to start once it has. To renew it, run `scripts/setup-github.sh interaction-limit <owner>/<repo>`.
