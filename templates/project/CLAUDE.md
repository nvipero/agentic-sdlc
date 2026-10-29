# Project entry point for agent sessions

This repository is built with the agent factory. GitHub is the source of truth:
stories are issues, specs are Markdown files in `specs/`, and work happens in pull requests.

## Where things are

| Path | Owner |
|---|---|
| `docs/product-context.md`, `docs/glossary.md`, `docs/research/` | researcher |
| `specs/` | spec writer |
| `tests/acceptance/` (its own npm package) | test writer |
| `src/`, `public/`, `tests/unit/`, and the project's root files (`package.json`, lockfile, `tsconfig.json`, Vite and lint configuration, `index.html`) | implementer |
| `.gitignore` | owner |

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
- Text for humans is short enough to read, and a question carries only the question. Pull request descriptions start with a TL;DR; messages and issue comments do not need one.
