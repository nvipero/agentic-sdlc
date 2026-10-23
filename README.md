# agentic-sdlc

An agent-driven software factory. A user story travels from a GitHub issue to a merged pull request. Agents specify, test, implement and review it, and the human sets direction, answers questions and accepts the result. The full design is in [specs/factory-v1-spec.md](specs/factory-v1-spec.md).

Status: step 1 (foundations) of five. Roles, skills and `/factory-run` come in later steps.

## What is here

| Path | Contents |
|---|---|
| `templates/project/` | Everything copied into a new project repository |
| `scripts/setup-github.sh` | Sets up GitHub protections, labels and the Projects board (six issue-only views, default view removed) for a repository |
| `scripts/exit-check.sh`, `scripts/redact.sh` | Step 1 exit check, and redaction of its output before publishing |
| `skills/`, `agents/`, `commands/` | Role knowledge, role definitions and commands (later steps) |
| `specs/`, `docs/` | Specification, plans and verification evidence |

## How the sandbox works

- **Container:** agents run in a dev container on your machine, started only with the project's `scripts/up.sh`.
- **Workspace:** a clone of the project inside a Docker volume, made with a fine-grained token scoped to that repository.
- **Read-only from the host:** `.factory/`, `.claude/`, `.github/`, `.devcontainer/` and `CLAUDE.md` are mounted read-only from your host clone of `main`.
- **Not visible in the container:** your host `.git` and `scripts/up.sh`.
- **Network:** outbound traffic is limited to an HTTPS allowlist (Anthropic, GitHub, npm). The firewall fails closed.
- **Claude Code policy:** set in `/etc/claude-code/managed-settings.json` inside the image. It disables connectors, artifacts, non-essential traffic and updates, and denies merge commands. Sessions start in bypass mode, and the deny rules still apply.
- **Factory definitions as a plugin:** `.factory/` loads as the Claude Code plugin `factory` from the read-only `/workspace/.factory`, so its commands are `/factory:<name>`. Managed settings allow no other source of skills, agents, hooks or plugins, so an agent cannot load a substitute.
- **Token:** `up.sh` passes the token to the container by name (`docker exec -e GH_TOKEN`), so it never appears in a process's argument list on your Mac.
- **GitHub protections:** a ruleset on `main` with no bypass actors, an interaction limit of collaborators only, secret scanning with push protection, and GitHub Actions disabled until step 4.
- **Preflight:** on every start, `up.sh` checks these and refuses to start if any check fails:
  - the repository's visibility
  - an active ruleset without bypass actors
  - the interaction limit
  - secret scanning
  - push protection
  - GitHub Actions is disabled
  - the host clone is clean, on `main` and equal to `origin/main`
- **The host clone is never updated automatically.** If it is behind `origin/main`, `up.sh` refuses to start. Review the new commits with `git log -p HEAD..origin/main`, then pull with `git pull --ff-only`.

**Known limitation until step 4:** agents act with the owner's GitHub identity, so the agent token can technically merge a pull request. The ruleset guarantees that changes reach `main` only through a pull request, not that a human merged it. A merged change is never executed on your Mac until you review and pull it yourself.

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
- `git` and `jq`

1. **Create the repository:** create an empty public repository on GitHub and clone it next to this one.
2. **Create the token:** a fine-grained token for that repository only, with Contents, Issues and Pull requests set to read and write. No other permissions, and an expiry of 30 to 90 days. Store it in 1Password at `op://Agent Factory/<repo-name>-github/credential`.
3. **Copy the template and push the first commit:**
   ```sh
   rsync -a templates/project/ ../<repo-name>/
   rsync -a --delete --exclude README.md skills agents commands templates/project/.factory/ ../<repo-name>/.factory/
   cd ../<repo-name> && git add -A && git commit -m "chore: initialize project from factory template" && git push -u origin main
   ```
4. **Apply the GitHub setup from this repo.** Run the ruleset after the first push, because it blocks direct pushes to `main`:
   ```sh
   scripts/setup-github.sh ruleset <owner>/<repo-name>
   scripts/setup-github.sh interaction-limit <owner>/<repo-name>
   scripts/setup-github.sh secret-scanning <owner>/<repo-name>
   scripts/setup-github.sh actions <owner>/<repo-name>
   scripts/setup-github.sh labels <owner>/<repo-name>
   scripts/setup-github.sh board <owner>/<repo-name>
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

## Updating a project's factory definitions

A project's `.factory/` is a copy of this repository's `skills/`, `agents/` and `commands/`, plus the template's `.factory/`. After a change here, copy it into the project on a branch, open a PR there, merge it, and pull the project's host clone:

```sh
rsync -a --delete --exclude README.md skills agents commands templates/project/.factory/ ../<repo-name>/.factory/
```

`README.md` files are left out, because every Markdown file in a plugin's `agents/` or `commands/` loads as an agent or a command. Changes to `.devcontainer/`, `CLAUDE.md` or `scripts/up.sh` are copied from `templates/project/` the same way.

## Renewing protections

The interaction limit expires after six months. `up.sh` warns 14 days before it expires, and refuses to start once it has. To renew it, run `scripts/setup-github.sh interaction-limit <owner>/<repo>`.
