# Project entry point for agent sessions

This repository is built with the agent factory. GitHub is the source of truth:
stories are issues, specs are Markdown files in `specs/`, and work happens in pull requests.

## Where things are

| Path | Owner |
|---|---|
| `docs/product-context.md`, `docs/glossary.md`, `docs/research/` | researcher |
| `specs/` | spec writer |
| `tests/acceptance/` (its own npm package) | test writer |
| `src/`, `public/`, `tests/unit/`, and the project's root files (`package.json`, lockfile, `tsconfig.json`, Vite and lint configuration, `index.html`, `deno.json`) | implementer |
| the paths of the database and API components in `.factory/config.yaml` (`components`), and the files their host names in `.github/scripts/hosts/` | implementer |
| `.gitignore`, and dot files outside the component paths | owner |

## Read-only for agents

`.factory/`, `.claude/`, `.github/`, `.devcontainer/` and this file are mounted read-only
from the owner's clone of `main`. Changes to them go through the factory repository,
never through this project. Do not try to work around this.

## Naming

- Commits follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/): `type(scope): description`, with the types `feat`, `fix`, `docs`, `chore`, `test`, `refactor`.
- Branches follow [Conventional Branch 1.1.0](https://conventionalbranch.org/): `<type>/<description>` in lowercase letters, digits and hyphens.
- Story branches: `feat/issue-<n>-<slug>` for a user story, `fix/issue-<n>-<slug>` for a bug, `chore/issue-<n>-<slug>` for a chore.

## Rules

- Never merge a pull request. The human merges.
- Never push to `main`. Work on a branch and open a pull request.
- Text for humans is short enough to read, and a question carries only the question. A pull request description or Markdown document longer than about 15 lines, or with more than two sections, starts with a TL;DR as a quote block (`> **TL;DR:** ...`); shorter ones, messages and issue comments do not need one.
