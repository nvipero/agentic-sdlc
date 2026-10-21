# Agent factory: v1 specification

Status: approved by owner, 2026-10-21  
Owner: Niko (human decision maker)  
Author: Claude (claude.ai planning session, 2026-10-13, revision 3)

## TL;DR

V1 proves that one user story can travel from a GitHub issue to a merged pull request with agents doing the specifying, testing, implementing and reviewing, and the human only setting direction, answering questions, settling disputes and accepting the result. Agents run in a sandboxed dev container on the owner's Mac with the least privileges their role needs. The factory and the projects it builds live in separate repositories, and no agent can change the factory's own definitions.

## 1. Purpose

A reusable, project-agnostic setup in which AI agents take a user story from idea to a reviewable preview. The human sets goals and priorities, validates specs and accepts results. Agents research, specify, test, implement and review each other's work. Deterministic tools act as hard gates.

V1 is not optimised for speed, parallelism or visuals.

## 2. Principles

Fixed for v1. Changing one requires an owner decision.

1. **GitHub is the single source of truth.** Stories are GitHub Issues, specs are Markdown files in the project repo, implementation happens in pull requests, status lives in labels and a GitHub Projects board (a view over the issues).
2. **Understanding comes before specification.** No agent writes a spec it cannot justify. Every spec states in the agent's own words what problem the story solves and why, traced to the project context. If the agent cannot do that, it asks the human instead.
3. **Every producing agent has a reviewer** with its own context. Producer and reviewer never share a session.
4. **Least privilege.** Every agent has the narrowest permissions that still let it do its role: limited tools, limited write paths, a repo-scoped token, and a network allowlist.
5. **Limits must be out of the agent's reach.** A rule an agent can edit is not a limit. Restrictions are enforced by the container, the file system, GitHub and CI, not only by instructions or agent-editable settings.
6. **Agents never modify factory definitions** inside a project repo. Changes to the factory happen in the factory repo through a pull request the human approves.
7. **Deterministic gates are not replaced by agents.** Lint, type checks, tests and security scans decide whether a change can merge. Agents cannot change gates.
8. **Acceptance tests are written before implementation** by a different agent than the implementer. The implementer cannot change them.
9. **Code is persistent and layered.** Changes are scoped to the story. Regenerating large parts of the codebase is a separate, human-approved decision.
10. **Work can move upstream as well as downstream.** Any role may return work to an earlier role with a reason. All handoffs go through the orchestrator and are recorded as comments in the issue or PR, so the full chain is visible when the human steps in.
11. **Disputes escalate on lack of progress,** not on a fixed round count alone.
12. **The human's attention is the scarcest resource.** Humans are pulled in only at defined points. When they are, they get a focused list of what deserves their judgement, not everything.
13. **Text is sized for its reader.** Output for humans starts with a TL;DR and is short enough to actually read. Output for agents may be as detailed as needed.
14. **Role knowledge is portable.** Each role's know-how lives in an Agent Skill (agentskills.io format). Role definitions are thin wrappers that choose the model, tools and skill, so a role can move to another model or tool later.

## 3. Scope

### In v1

- **Two repositories:** the factory repo (`agentic-sdlc`), and one throwaway test project repo (`sdlc-pilot`) created from the factory's project template. Each project has its own repo, issues and Projects board.
- A dev container per project as the agents' sandbox, run with Rancher Desktop.
- Roles: orchestrator, researcher (project level), spec writer, spec reviewer, test writer, implementer, code reviewer.
- Role knowledge as Agent Skills.
- Labels, issue template and a Projects board as the human interface.
- Deterministic gates in GitHub Actions, including guards that protect factory definitions, gates and acceptance tests.
- Preview deployment per pull request.

### Out of v1 (backlog, rough order)

1. Separate architecture and security reviewers (v1 code reviewer covers both with a checklist).
2. Any role switchable to another model, including Codex.
3. Optional roles: architect (ADRs and infrastructure as code), designer, story-level researcher for technical unknowns.
4. Gatekeeper role that evaluates and implements justified changes to gates, always visible to the human.
5. Codebase-wide security auditor running outside the pipeline on a schedule, reporting findings as issues.
6. Stack-fit check: researcher or architect raises justified reasons to use something other than the default stack.
7. Retro agent and evals for the factory itself. The retro agent cannot change skills or instructions. Its output is a proposal: observed problem, evidence (links to issues, PRs, disputes, gate failures) and suggested change. First it posts proposals to the project issue tracker with the label `factory-feedback` and the human decides whether to move them to the factory repo. Later it may create issues in the factory repo directly with a separate token limited to issues only. Changes are always made in the factory repo through a PR the human approves. The retro agent does not need to run in the project container.
8. Parallel alternative implementations for uncertain stories.
9. Agents get their own GitHub identity (for example a GitHub App), enabling branch protection and CODEOWNERS rules that separate agent changes from human changes.
10. Factory distributed as a Claude Code plugin instead of a copied template.
11. Fresh container per story, managed by an orchestrator outside the container.
12. Orchestrator triggered by labels instead of a manual command.
13. Generating project-specific dev containers through a skill.
14. Custom dashboard.
15. Using the factory to develop the factory itself.
16. Optional spec-first pull request merged before implementation.
17. 1Password service account limited to the factory vault only, so that even the start script cannot read other vaults (availability and cost to be checked).

## 4. Architecture

### Where things run

| Component | Location |
|---|---|
| Stories, specs, PRs, status | GitHub, private repositories |
| Agents | Claude Code inside the project's dev container on the owner's Mac |
| Container runtime | Rancher Desktop, engine dockerd (moby) |
| Deterministic gates | GitHub Actions |
| Preview | Vercel preview deployment per PR |

### Container lifecycle

- One dev container per project. The human starts it with the project's start script (`scripts/up.sh`) when working on the project and stops it afterwards.
- Each story gets its own git worktree inside the container.
- Agents cannot start, stop or control containers. The container has no access to the Docker socket.
- Inside the container, Claude Code runs without per-command permission prompts. Limits come from the container boundary, the network allowlist, read-only mounts and role tool restrictions.

### Factory repository

The factory repo follows the same layout conventions as project repos (specs in `specs/`, background in `docs/`), so that the factory can later be developed with the factory without restructuring.

```
skills/              one Agent Skill per role (SKILL.md + references)
agents/              thin role definitions: model, tools, skill
commands/            factory-run and other factory commands
templates/project/   everything copied into a new project repo
specs/
  factory-v1-spec.md this document
docs/                background and reference material for the factory
README.md            how to start a new project with the factory
```

### Project repository (created from the template)

```
.factory/            config.yaml and copied skills, agents, commands   (read-only for agents)
.claude/             Claude Code settings                              (read-only for agents)
.github/             workflows, issue templates, PR template           (read-only for agents)
.devcontainer/       container definition and network allowlist        (read-only for agents)
CLAUDE.md            entry point for agent sessions                    (read-only for agents)
scripts/up.sh        container start script                            (read-only for agents)
docs/
  product-context.md goal, users, constraints, non-goals               (researcher)
  glossary.md        domain terms                                      (researcher)
specs/               refined spec per story                            (spec writer)
tests/acceptance/    acceptance tests                                  (test writer)
src/, tests/unit/    production code and unit tests                    (implementer)
```

Read-only paths are mounted read-only into the container, so no command inside it can change them. The exact mount setup is verified in step 1.

### Configuration (`.factory/config.yaml`)

```yaml
roles:
  researcher:    { model: opus }
  spec-writer:   { model: opus }
  spec-reviewer: { model: sonnet }
  test-writer:   { model: sonnet }
  implementer:   { model: opus }
  code-reviewer: { model: opus }
disputes:
  max_rounds: 4
  escalate_when_no_progress_for: 2   # consecutive rounds repeating the same findings
light_path:
  allowed_for_labels: [trivial]      # skip spec review and acceptance tests
```

Model choices are initial guesses and will be tuned after the first stories. The config is owned by the human.

### Credentials

- **One fine-grained GitHub token per project,** scoped to that project's repo only. Permissions: contents, issues and pull requests (read and write). No workflow permission, so the token cannot change GitHub Actions files. No admin rights. Expiry 30 to 90 days, then rotated.
- **Storage:** tokens live in a dedicated 1Password vault ("Agent Factory"), separate from personal and client credentials. A token is never stored as a file in a repository or on the container's disk.
- **Delivery, with clear separation of responsibilities:**
  - 1Password only stores and returns secrets.
  - The devcontainer CLI only starts the container.
  - The project's start script `scripts/up.sh` connects them: it reads the token with `op read`, sets it as an environment variable for its own run, and starts the container with the devcontainer CLI. `devcontainer.json` passes the variable into the container (`${localEnv:...}`).
  - The secret source is a replaceable step in the script. Switching to Keychain or another manager changes only that step.
- **The 1Password CLI is never installed in the container.** Access to the vault would expose all other credentials.
- Starting the container from the VS Code UI does not pass the token. The container is started from the terminal with the start script.
- No other credentials are placed in the container. Claude Code's own credentials are the only exception and are treated as exposed if the container is compromised.
- Anything given to the container can be read by agents. Protection comes from limiting the scope and lifetime of credentials, not from hiding them.

### Labels

- Type: `user-story`, `bug`, `chore`, `trivial`
- State: `ready-for-factory`, `needs-human`, `spec-approved`, `dispute`, `gate-change`, `tests-change-approved`

## 5. Workflow

| Status | Who acts | Exit condition |
|---|---|---|
| Idea | Human: writes story, sets priority | Label `ready-for-factory` (requires approved project context) |
| Spec | Spec writer, then spec reviewer | Reviewer approves, or questions exist |
| Waiting for human | Human: answers questions, approves spec | Label `spec-approved` |
| Tests | Test writer, then code reviewer checks coverage | Acceptance tests committed |
| Implementation | Implementer and code reviewer, may debate | Reviewer approves and gates pass |
| Dispute | Human: decides | Decision recorded in the PR |
| Preview | Human: evaluates preview against the story | Human approves PR |
| Done | Merged | - |

### Project context (once per project, updated as needed)

1. The researcher interviews the human: purpose, users, domain terms, constraints, non-goals. It may read material and code the human points to.
2. The researcher writes `docs/product-context.md` and `docs/glossary.md`, listing uncertainties as open questions.
3. The human corrects and approves the context. Stories are not accepted before this.
4. When a story reveals the context is wrong or incomplete, the context is updated through a PR the human approves.

### Branch model

One branch and one pull request per story. Commits come in order: spec, acceptance tests, implementation. Each role writes only to its own paths (section 4), and CI enforces this. Everything is merged together at the end, so the PR shows the whole chain.

### Story to spec

1. The human writes a story with the issue template: goal, user value, acceptance criteria in plain language, priority.
2. **Understanding check.** The spec writer first writes a "Problem and why" section in its own words, traced to the project context. If it cannot, it asks in the issue or returns the story to the researcher.
3. The spec writer produces `specs/<issue>-<slug>.md`: problem and why, scope, out of scope, testable acceptance criteria, assumptions, open questions.
4. The spec writer never guesses silently. Assumptions are listed. Questions are posted to the issue, which gets `needs-human`.
5. The spec reviewer checks ambiguity, missing edge cases, testability and consistency with the project context.
6. The human answers questions in the issue and adds `spec-approved`.

### Spec to merge

1. The test writer turns the approved acceptance criteria into automated acceptance tests.
2. The implementer works in the story's worktree and opens a draft PR.
3. The code reviewer reviews against the spec, conventions, architecture boundaries and the security checklist.
4. Implementer and reviewer may debate. On escalation the PR gets `dispute` and a short summary: the disagreement, both positions, what each option costs.
5. When the reviewer approves and gates pass, the PR is marked ready and the preview link is posted to the issue.
6. The PR description contains a **"Where to look"** section for the human: restricted-list hits, deviations from the spec, assumptions made, and places where the reviewer is uncertain. The human reads this section and the preview, not the whole diff.
7. The human merges, or comments with changes, which restarts implementation.

## 6. Roles

Each role is an Agent Skill plus a thin role definition stating model, tools and skill.

| Role | Input | Output | Writes to | Must not |
|---|---|---|---|---|
| Orchestrator | Issue | Path choice, role order, labels, handoff comments | Labels, comments | Write code, specs or tests |
| Researcher | Human interview, existing material | Project context, glossary | `docs/` | Present guesses as facts |
| Spec writer | Issue, context, codebase | Spec, questions | `specs/` | Guess silently, or write a spec it cannot justify |
| Spec reviewer | Spec, issue, context | Findings | Comments only | Edit files |
| Test writer | Approved spec | Acceptance tests | `tests/acceptance/` | Write production code |
| Implementer | Spec, tests | Code, unit tests, draft PR | `src/`, `tests/unit/` | Touch acceptance tests, specs or anything outside the story |
| Code reviewer | PR, spec | Findings, approval, "Where to look" | Comments, PR description | Edit files |

In v1 the orchestrator is a Claude Code command (`/factory-run <issue>`) run in the main session, which delegates to role subagents.

## 7. Restricted list

Always requires the human: authentication and authorisation changes, data deletion or migration, new external services or paid dependencies, and any change to factory definitions, gates or permissions.

## 8. Deterministic gates (GitHub Actions)

Required checks on every PR:

- Type check, lint, unit tests, acceptance tests
- Dependency vulnerability audit
- Secret scanning
- **Path ownership guard:** each commit stage touches only its role's paths
- **Acceptance test guard:** implementation commits may not modify acceptance tests unless the human added `tests-change-approved`
- **Factory definitions guard:** fails if the PR modifies `.factory/`, `.claude/`, `.github/`, `.devcontainer/`, `scripts/up.sh` or `CLAUDE.md`
- **Gate change visibility:** any change to gate configuration is labelled `gate-change` and needs a written justification in the PR description

Exact static analysis tools are chosen in step 4 and checked for current pricing and availability on private repositories.

## 9. Test project defaults

- TypeScript, React with Vite, Node.js
- Vitest for unit tests, Playwright for acceptance tests
- Vercel for preview deployments

The topic is chosen by the owner. Small, disposable and justifiable as work.

## 10. Build steps

Each step ends with an exit check, and the next starts only after the owner has seen the result.

1. **Foundations.** Factory repo, project template, test project repo, dev container with network allowlist and read-only mounts, start script with token from 1Password, scoped token, labels, issue template, Projects board, README. Exit: an agent inside the container cannot modify factory definitions, cannot reach non-allowlisted hosts, and cannot see anything outside the project workspace.
2. **Context and spec chain.** Researcher, spec writer with understanding check, spec reviewer, question flow. Exit: approved project context, and one story with an approved spec where at least one question was answered through the issue.
3. **Implementation chain.** Test writer, implementer, code reviewer, `/factory-run`. Exit: the story reaches a PR with passing local tests, a reviewer approval and a "Where to look" section.
4. **Gates and preview.** All gates in section 8 and Vercel preview. Exit: a PR that breaks any gate cannot be merged, and every PR gets a preview link.
5. **First full run.** A new story from idea to merge without manual code edits. Exit: definition of done met and problems recorded.

## 11. Definition of done for v1

- A story written by the human reaches a merged PR without the human editing code.
- The human was asked only at defined points, and each human-facing message started with a TL;DR.
- The spec's problem and why section is traceable to the approved project context.
- All gates ran and were required for merge.
- No agent modified acceptance tests, factory definitions or gates.
- No agent accessed anything outside its container workspace or allowlisted network.
- Observed problems are written down for the next iteration.

## 12. Known risks

- **Building the factory becomes the project.** Mitigation: strict scope and exit checks per step. V1 has grown during planning, so further additions go to the backlog.
- **Dev container setup takes longer than expected.** It is the biggest single piece of new work in v1, but adding it later would cost more.
- **Subscription limits.** Agent runs share the Team plan quota with the owner's other work.
- **Agent loops.** Mitigation: turn limits and dispute rules.
- **Specs approved without reading.** Mitigation: questions and assumptions are surfaced separately.
- **Copied templates drift** from the factory as it evolves. Accepted in v1. Plugin distribution is in the backlog.

## 13. Open questions for the owner

- Test project topic.
- Vercel account for previews.
