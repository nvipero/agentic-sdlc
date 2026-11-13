# Architecture

## Where things run

| Component | Location |
|---|---|
| Stories, specs, PRs, status | GitHub, public repositories with enforced protections |
| Agents | Claude Code inside the project's dev container on the owner's Mac |
| Container runtime | A Docker engine with the `docker` CLI; tested on Rancher Desktop with dockerd (moby) |
| Deterministic gates | GitHub Actions |
| Preview and production | Vercel or Cloudflare Workers, the frontend component's host ([components](#components)) |

The factory (`agentic-sdlc`) and each project it builds live in separate repositories. A project is created from the factory's project template and has its own repo, issues and Projects board. `sdlc-pilot`, a Todo-app, is the test bed for factory changes.

## Factory repository

```
skills/              one Agent Skill per role (SKILL.md + references)
agents/              thin role definitions: model, tools, skill
commands/            factory commands such as /factory:run and /factory:context
templates/project/   everything copied into a new project repo
plugins/assist/      the assist plugin: the roles for one task in any existing repository
.claude-plugin/      local marketplace that installs plugins/ at user scope on the host
docs/                how the factory works, and evidence from its verification
scripts/             GitHub setup, exit checks and helpers (run on the host)
README.md            overview and entry point
CLAUDE.md            working rules for changes to the factory
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
                     tsconfig, Vite and lint configuration, index.html,
                     deno.json)
<component paths>    the database and API components ([components](#components)),   (implementer)
                     with the files their host names; for supabase:
                     supabase/migrations/, supabase/functions/,
                     config.toml, seed.sql (created with supabase init)
supabase/supabase.lock  the local stack's service versions, a copy of  (human)
                     .devcontainer/supabase.lock
.gitignore, dot files outside the component paths                      (human)
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
- **Supabase local stack for acceptance tests:** the Supabase CLI (`SUPABASE_VERSION`) and its native runtime's service archives, pinned by `.devcontainer/supabase.lock`, are in the image, so a project with Supabase components runs its acceptance tests against a local stack in the container, with no container engine and no download (`.github/scripts/supabase-stack.sh`). Studio, analytics and the pooler are left out; the rest adds about 1 GB to every project's image. The stack listens on loopback, its keys are the CLI's published demo values, and the CLI's telemetry is off. It is the CLI's experimental stack ([risks](risks.md)).
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
components:                         # the parts of the service (below)
  web: { kind: frontend, path: ., host: vercel, spa: false }
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

### Components

`components` names the parts of the service: what each one is (`kind`), where it is in the repository (`path`) and where it runs (`host`). The names (`web`, `db`) are the owner's; the factory reads only the fields. `.github/scripts/components.sh` reads and validates them for the guards, the deploy workflows, the tests workflow and the exit check, from `main`'s `config.yaml` in the guards and the deploy workflows (the `tests` workflow reads the PR's checkout, only to find the Deno paths and whether to start the Supabase stack); the orchestrator reads the file itself, because the container has no Ruby.

```yaml
components:
  web:       { kind: frontend, path: .,                   host: vercel, spa: false }
  db:        { kind: database, path: supabase/migrations, host: supabase }
  functions: { kind: api,      path: supabase/functions,  host: supabase }
```

Supported now, and anything else fails with a message:

- **`frontend`:** exactly one, at `path: .` (the root rules: `src/`, `public/`, `tests/unit/`, root project files), on `vercel` or `cloudflare` (`.github/scripts/deploy/<host>.sh`). `spa: true` serves `index.html` for unknown paths, `cloudflare` only.
- **`database` and `api`:** at most one of each, on a host with a descriptor `.github/scripts/hosts/<host>.yaml`: the path the host fixes for each kind, the files the implementer owns besides the paths, the files listed for "Where to look", and the kinds tested with Deno. Only `supabase` now; `production-deploy` deploys them before the frontend ([gates](gates.md#production)).
- **Role guidance per host:** `skills/implementer/references/<host>.md` and `skills/code-reviewer/references/<host>.md`. The role skills hold only what applies to any database or API.

Components in other repositories, more than one API, a diagram generated from the components and more hosts are backlog issues ([#65](https://github.com/nvipero/agentic-sdlc/issues/65), [#66](https://github.com/nvipero/agentic-sdlc/issues/66), [#67](https://github.com/nvipero/agentic-sdlc/issues/67)).

## Project defaults

- TypeScript, React with Vite, Node.js
- Vitest for unit tests, Playwright for acceptance tests
- Optionally Supabase as the `database` and `api` components' host: Postgres migrations with row level security, Deno Edge Functions with Deno's test runner (Deno 2.1, as Supabase's Edge Runtime; dependencies from npm only, so the firewall needs no other host). Acceptance tests run against Supabase's local stack, in the container and in the `tests` workflow ([gates](gates.md)). `main` deploys to one production Supabase project; preview backends are not supported yet ([#60](https://github.com/nvipero/agentic-sdlc/issues/60)), so a Supabase app's preview has no backend.
- Vercel for preview and production deployments (frontend `host: vercel`; Hobby, through the pipeline; no Git integration), or a Cloudflare Worker with static assets only (frontend `host: cloudflare`; through the pipeline; no Git integration)
