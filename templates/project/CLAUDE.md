# Project entry point for agent sessions

This repository is built with the agent factory. GitHub is the source of truth:
stories are issues, specs are Markdown files in `specs/`, and work happens in pull requests.

## Where things are

| Path | Owner |
|---|---|
| `docs/product-context.md`, `docs/glossary.md` | researcher |
| `specs/` | spec writer |
| `tests/acceptance/` | test writer |
| `src/`, `tests/unit/` | implementer |

## Read-only for agents

`.factory/`, `.claude/`, `.github/`, `.devcontainer/` and this file are mounted read-only
from the owner's clone of `main`. Changes to them go through the factory repository,
never through this project. Do not try to work around this.

## Rules

- Never merge a pull request. The human merges.
- Never push to `main`. Work on a branch and open a pull request.
- Output for humans starts with a TL;DR.
