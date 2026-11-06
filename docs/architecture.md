# Architecture

## Where things run

| Component | Location |
|---|---|
| Stories, specs, PRs, status | GitHub, public repositories with enforced protections |
| Agents | Claude Code inside the project's dev container on the owner's Mac |
| Container runtime | Rancher Desktop, engine dockerd (moby) |
| Deterministic gates | GitHub Actions |
| Preview and production | Vercel |

The factory (`agentic-sdlc`) and each project it builds live in separate repositories. A project is created from the factory's project template and has its own repo, issues and Projects board. `sdlc-pilot`, a Todo-app, is the test bed for factory changes.

## Factory repository

```
skills/              one Agent Skill per role (SKILL.md + references)
agents/              thin role definitions: model, tools, skill
commands/            factory commands such as /factory:run and /factory:context
templates/project/   everything copied into a new project repo
docs/                how the factory works, and evidence from its verification
scripts/             GitHub setup, exit checks and helpers (run on the host)
README.md            overview and entry point
```

Changes to the factory start from an issue in the [backlog](https://github.com/users/nvipero/projects/2). If the factory is ever developed with the factory ([#43](https://github.com/nvipero/agentic-sdlc/issues/43)), story specs go to `specs/` as in projects.

## Project repository (created from the template)

```
.factory/            factory plugin: config.yaml, copied skills, agents, commands   (read-only for agents)
.claude/             Claude Code settings                              (read-only for agents)
.github/             workflows and their scripts, CODEOWNERS,          (read-only for agents)
                     issue templates
.devcontainer/       container definition and network allowlist        (read-only for agents)
CLAUDE.md            entry point for agent sessions                    (read-only for agents)
scripts/up.sh        container start script                            (not in the container)
docs/
  product-context.md goal, users, constraints, non-goals               (researcher)
  glossary.md        domain terms                                      (researcher)
  research/          answers to research requests, per story          (researcher)
specs/               refined spec per story                            (spec writer)
tests/acceptance/    acceptance tests by feature, tagged per story     (test writer)
                     criterion; their own npm package
src/, public/,       production code, static files, unit tests, and    (implementer)
tests/unit/          the root project files (package.json, lockfile,
                     tsconfig, Vite and lint configuration, index.html)
.gitignore                                                             (human)
```

`.factory/` is a Claude Code plugin named `factory`, loaded from the read-only `/workspace/.factory` through managed settings, so its commands are `/factory:<name>` and its roles `factory:<role>`. Managed settings allow no other source of skills, agents, hooks or plugins, so an agent cannot load a substitute.

`.factory/`, `.claude/`, `.github/`, `.devcontainer/` and `CLAUDE.md` are mounted read-only from the owner's host clone of `main`, so no command inside the container can change them. `scripts/up.sh` is not in the container at all. Agents can still create commits that change these paths; the `guards` check rejects them ([gates](gates.md)).

A project's `.factory/` is a copy of the factory's `skills/`, `agents/` and `commands/`, plus the template's `.factory/`. Copies drift from the factory until they are updated ([setup](setup.md#updating-a-projects-factory-definitions)).

## Dev container

- One dev container per project. The human starts it with the project's start script (`scripts/up.sh`) when working on the project and stops it afterwards. Only containers started by the start script get the token mount; starting the container any other way, such as from the VS Code UI, skips the token, the workspace setup and the exec guard.
- Stories run one at a time on their branch in `/workspace`. There are no story worktrees: the read-only paths exist only in `/workspace`, and the factory is not optimised for parallel stories. Parallel stories would come with a fresh container per story ([#48](https://github.com/nvipero/agentic-sdlc/issues/48)).
- **Workspace:** a clone of the project repo in a Docker volume, made with the agents' GitHub App token, not the host clone. The host `.git` is not visible in the container. The container is recreated on every start, and the volumes persist. The workspace is never deleted automatically: `scripts/up.sh reset-workspace` archives it before replacing it.
- Agents cannot start, stop or control containers. The container has no access to the Docker socket.
- **Network:** outbound traffic is limited to an HTTPS allowlist (Anthropic, GitHub, npm). The firewall fails closed.
- **Browser for acceptance tests:** Playwright's Chromium is installed in the image at build time, pinned with `PLAYWRIGHT_VERSION` in the Dockerfile, so no browser download passes the firewall. A project's `tests/acceptance/package.json` pins `@playwright/test` to the same version; changing it means changing the Dockerfile, which rebuilds the image.
- **Claude Code policy:** set in `/etc/claude-code/managed-settings.json` inside the image. It disables connectors, artifacts, non-essential traffic and updates, and denies merge commands. Claude Code runs without per-command permission prompts (bypass mode), and the deny rules still apply. Limits come from the container boundary, the network allowlist, read-only mounts, managed settings in the image and role tool restrictions.

Credentials and GitHub protections are in [security](security.md).

## Configuration (`.factory/config.yaml`)

```yaml
language:
  conversation: fi   # the session with the owner
  repository: en     # everything written to the repository and GitHub
roles:
  researcher:    { model: opus }   # research requests only; the interview uses the session model
  spec-writer:   { model: opus }
  spec-reviewer: { model: sonnet }
  test-writer:   { model: sonnet }
  implementer:   { model: opus }
  code-reviewer: { model: opus }
acceptance:                         # how acceptance tests start the app
  start: "npm run dev -- --strictPort"   # run at the repository root
  url: "http://localhost:5173"
disputes:
  max_rounds: 4
  escalate_when_no_progress_for: 2   # consecutive rounds repeating the same findings
  rework_resets: 1                   # a rework restarts the round count this many times, then escalates
light_path:
  allowed_for_labels: [trivial]      # skip spec review and acceptance tests
```

The acceptance tests are written before the app exists, so the `acceptance` contract tells the test writer and the implementer how the app is started. The browsers come with the container image, pinned to one Playwright version, and the acceptance package pins `@playwright/test` to the same version.

Model choices are initial guesses, to be tuned with more stories. The config is owned by the human.

## Project defaults

- TypeScript, React with Vite, Node.js
- Vitest for unit tests, Playwright for acceptance tests
- Vercel for preview and production deployments (Hobby, through the pipeline; no Git integration)
