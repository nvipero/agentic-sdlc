# Working on the agent factory

This repository is the factory itself: role skills, agents, commands, the project template and the host scripts. How the factory works is in `docs/` (start from the table in `README.md`); those docs are the source of truth, not memory or older text.

## Where work comes from

- Every change starts from an issue in the [agentic-sdlc backlog](https://github.com/users/nvipero/projects/2). The owner sets the order and asks for issues to be done one at a time.
- The plan goes into the issue, the evidence into the pull request. A dependency is a GitHub "blocked by" link on the issue.
- Something new found while working becomes a backlog issue, not a note in a document.

## Keeping the docs current

Before opening a pull request:

1. Search `README.md`, `CLAUDE.md` and `docs/` (not `docs/evidence/`, which is history) for every name the change touches: paths, scripts, workflows, labels, commands, settings. For example `grep -rn "<name>" README.md CLAUDE.md docs --exclude-dir=evidence`.
2. Update every statement the change makes false, in the same pull request.
3. End the pull request description with a line `Docs:` that names the documents updated, or says `checked, no change`.

## Conventions

- Commits and branches: Conventional Commits and Conventional Branch, as in `docs/workflow.md`, "Naming conventions".
- Everything written to the repository and GitHub is in English.
- Never merge a pull request. The owner merges.
- `skills/`, `agents/`, `commands/` and `templates/project/` reach a project only when it is synced (`docs/setup.md`); say in the pull request whether the pilot needs a sync.
