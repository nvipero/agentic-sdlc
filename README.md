# agentic-sdlc

An agent-driven software factory. A user story travels from a GitHub issue to a merged pull request. Agents specify, test, implement and review it, and the human sets direction, answers questions and accepts the result.

Status: v1 done (2026-10-31); [history](docs/history.md). `/factory:context` writes the project context, and `/factory:run` takes a story from spec to a pull request ready for your review: spec, your approval, acceptance tests, implementation, code review and the GitHub gates. Agents run in a sandboxed dev container and act as a GitHub App, a PR merges only with your approval, every PR marked ready gets a Vercel preview, and every merge deploys `main` to production. Further work is in the [backlog](https://github.com/users/nvipero/projects/2).

## Documentation

| Document | Contents |
|---|---|
| [Principles](docs/principles.md) | Purpose and the fixed principles |
| [Architecture](docs/architecture.md) | Repositories, the dev container, configuration, project defaults |
| [Workflow and roles](docs/workflow.md) | Statuses, labels, story to spec to merge, roles, restricted list |
| [Gates and deployment](docs/gates.md) | Required checks, preview, production |
| [Security](docs/security.md) | GitHub protections, the agents' identity and credentials, preflight |
| [Risks](docs/risks.md) | Known risks and accepted limitations |
| [Setup](docs/setup.md) | Starting a project, updating its factory definitions, renewing protections |
| [History](docs/history.md) | How v1 was built, and the evidence from its verification |

The docs describe the factory as it is now; a change that alters behaviour updates them in the same pull request.

## What is here

| Path | Contents |
|---|---|
| `skills/`, `agents/`, `commands/` | Role knowledge, role definitions and commands |
| `templates/project/` | Everything copied into a new project repository |
| `scripts/setup-github.sh` | Sets up GitHub protections, labels and the Projects board (six issue-only views, default view removed) for a repository |
| `scripts/exit-check.sh`, `scripts/redact.sh` | Exit check, and redaction of its output before publishing |
| `docs/` | The documents above; `docs/evidence/` holds verification evidence |

## Conventions

- **Commits and branches:** Conventional Commits and Conventional Branch ([workflow](docs/workflow.md#naming-conventions)), here and in project repos.
- **Backlog:** changes to the factory start from an issue in the [agentic-sdlc backlog](https://github.com/users/nvipero/projects/2) project, top of the list first; the owner sets the order. Mark a dependency with GitHub's "blocked by" link on the issue. The issue holds the plan, and the pull request holds the evidence.
