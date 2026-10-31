# Agent factory: v1 specification

Status: approved by owner, 2026-10-21  
Owner: Niko (human decision maker)  
Author: Claude (claude.ai planning session, 2026-10-13, revision 5)  
Revision 6, 2026-10-23: aligned with the step 1 implementation (preflight, read-only paths, token delivery, GitHub Actions disabled until step 4)  
Revision 7, 2026-10-29, with step 2: naming conventions, the factory plugin and its commands, research before asking with source tags, research requests, review loop rules, configurable languages, and quieter issue comments (principles 10 and 13, owner decision)  
Revision 8, 2026-10-29, with step 3: no story worktrees in v1, the acceptance test package and its start contract, root project files owned by the implementer, the orchestrator runs the tests and opens the pull request, two code review gates, the wrong-test path, acceptance tests named by feature with per-criterion tags, test-driven unit tests by the implementer, and the layered sandbox as the first step of v2 (owner decision)  
Revision 9, 2026-10-31, with step 4: principle 15 "Trust, but verify", the GitHub App as the agents' identity with host-minted one-hour tokens, owner-only labels and trusted input checked by account, the ruleset with code owner review and required gates, restricted GitHub Actions, the gates as built, the Vercel preview, feature-removal stories, and backlog items 21 and 22 (owner decisions)  
Revision 10, 2026-10-31, with step 5: the definition of done follows principle 13 on TL;DRs (owner decision)  
Revision 11, 2026-10-31, with step 5: v1 done; step 5 evidence in `docs/verification/step-5.md`  
Revision 12, 2026-10-31, after v1: deployment of `main` to production (backlog item 22, owner decision); plan `docs/plans/main-deploy.md`

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
10. **Work can move upstream as well as downstream.** Any role may return work to an earlier role with a reason. All handoffs go through the orchestrator and are recorded in the issue or PR, so the full chain is visible when the human steps in. The chain lives in one status comment that is edited in place; new comments are posted only when they have value to the human or another agent (questions, disputes, a result ready for review), because every comment is a notification.
11. **Disputes escalate on lack of progress,** not on a fixed round count alone.
12. **The human's attention is the scarcest resource.** Humans are pulled in only at defined points. When they are, they get a focused list of what deserves their judgement, not everything.
13. **Text is sized for its reader.** Output for humans is short enough to actually read, and a question to the human carries only the question. Pull request descriptions and long documents start with a TL;DR as a quote block (`> **TL;DR:** ...`, owner, 2026-10-31); issue comments do not need one. Output for agents may be as detailed as needed.
14. **Role knowledge is portable.** Each role's know-how lives in an Agent Skill (agentskills.io format). Role definitions are thin wrappers that choose the model, tools and skill, so a role can move to another model or tool later.
15. **Trust, but verify.** When a check after the fact is cheap, it is added even if an earlier control (permissions, rules, gates) should already be enough. Controls are layered, not either-or (owner decision, 2026-10-30).

## 3. Scope

### In v1

- **Two repositories:** the factory repo (`agentic-sdlc`), and one throwaway test project repo (`sdlc-pilot`) created from the factory's project template. Each project has its own repo, issues and Projects board.
- A dev container per project as the agents' sandbox, run with Rancher Desktop.
- Roles: orchestrator, researcher (project level), spec writer, spec reviewer, test writer, implementer, code reviewer.
- Role knowledge as Agent Skills.
- Labels, issue template and a Projects board as the human interface.
- Deterministic gates in GitHub Actions, including guards that protect factory definitions, gates and acceptance tests.
- Preview deployment per pull request; deployment of `main` to production on every merge (revision 12).

### Out of v1 (backlog, rough order)

1. Separate architecture and security reviewers (v1 code reviewer covers both with a checklist).
2. Any role switchable to another model, including Codex.
3. Optional roles: architect (ADRs and infrastructure as code), designer, story-level researcher for technical unknowns.
4. Gatekeeper role that evaluates and implements justified changes to gates, always visible to the human.
5. Codebase-wide security auditor running outside the pipeline on a schedule, reporting findings as issues.
6. Stack-fit check: researcher or architect raises justified reasons to use something other than the default stack.
7. Retro agent and evals for the factory itself. The retro agent cannot change skills or instructions. Its output is a proposal: observed problem, evidence (links to issues, PRs, disputes, gate failures) and suggested change. First it posts proposals to the project issue tracker with the label `factory-feedback` and the human decides whether to move them to the factory repo. Later it may create issues in the factory repo directly with a separate token limited to issues only. Changes are always made in the factory repo through a PR the human approves. The retro agent does not need to run in the project container.
8. Parallel alternative implementations for uncertain stories.
9. CODEOWNERS rules and finer-grained permissions per role, built on the agent identity introduced in step 4.
10. Factory distributed as a Claude Code plugin instead of a copied template.
11. Fresh container per story, managed by an orchestrator outside the container. Merged with the layered sandbox (a researcher container with open web access, a strict development container, and a deterministic host gatekeeper between them) as the **first step of v2** (owner decision, 2026-10-29).
12. Orchestrator triggered by labels instead of a manual command.
13. Generating project-specific dev containers through a skill.
14. Custom dashboard.
15. Using the factory to develop the factory itself.
16. Optional spec-first pull request merged before implementation.
17. 1Password service account limited to the factory vault only, so that even the start script cannot read other vaults (availability and cost to be checked).
18. Private project support through a GitHub organization on the Team plan, with the step 1 exit check repeated in a private repository.
19. Inspection mode: attach VS Code to the container only while agents are stopped, with credential forwarding disabled and VS Code hosts allowlisted only for that mode.
20. Mutation testing as a gate on unit test strength, if review and coverage prove too weak (owner decision, 2026-10-29: not in v1, it is slow).
21. Dependency updates by Dependabot, weekly and grouped: npm and GitHub Actions in project repositories, the Node base image digest and Actions in the factory repository; the guards then let `dependabot[bot]` change only manifests and lock files. The Claude Code and Playwright pins stay a manual monthly check (owner decision, 2026-10-30).
22. ~~Production deployment of `main` through the pipeline.~~ Done in revision 12 (section 8, "Production").

## 4. Architecture

### Where things run

| Component | Location |
|---|---|
| Stories, specs, PRs, status | GitHub, public repositories with enforced protections |
| Agents | Claude Code inside the project's dev container on the owner's Mac |
| Container runtime | Rancher Desktop, engine dockerd (moby) |
| Deterministic gates | GitHub Actions |
| Preview | Vercel preview deployment per PR |

### Repository visibility and protections

Both repositories are public. On a free GitHub account, rulesets and branch protection are enforced only in public repositories, and principle 5 requires enforced limits. The factory definitions would be public anyway, because the project template copies them into every project repo.

Applied to both `agentic-sdlc` and `sdlc-pilot`:

- **Ruleset on `main`:** pull request required, force pushes and deletion blocked.
  - **Project repositories (from step 4):** one approval, **review from code owners required** (`.github/CODEOWNERS` names only the owner), approvals dismissed by a new push, the gate checks required with GitHub Actions as their source, and CodeQL alerts of high severity blocking. One bypass actor: the admin role, in pull request mode, so the owner's own PRs (factory updates) merge without a second reviewer but never by direct push. The agents' App is not an admin and cannot bypass.
  - **The factory repository:** no required approvals (single maintainer), no checks (it runs no workflows), no bypass actors.
- **A merged branch is deleted automatically.**
- **Interaction limit "repository collaborators only":** outsiders cannot open issues or PRs, comment, react or edit. This keeps outside text out of agent input. The limit expires after at most six months.
- **Secret scanning and push protection** enabled.
- **GitHub Actions (projects, from step 4):** only GitHub-owned actions, pinned to a full commit SHA; a read-only `GITHUB_TOKEN` that cannot approve or create pull requests; approval required for every outside contributor's run; no repository-level secrets (the Vercel token is in the `preview` and `production` environments, deployable from `main` only); `pull_request_target` allowed by an Actions policy for `guards.yml` only, ahead of GitHub's default block on public repositories. The agents' App has no Workflows permission, so agents cannot change what runs. The dependency graph (needed by dependency review, turned on by hand) and CodeQL default setup are on. The factory repository keeps Actions disabled.

`scripts/up.sh` verifies on the host, before starting the container, that the repository visibility is as expected, every ruleset is active and the project ruleset is as above, the interaction limit is active, secret scanning and push protection are on, and the Actions settings, policy, dependency graph and CodeQL are as above. It also checks that the host clone is clean, on `main` and equal to `origin/main`; it never updates the host clone itself. If any check fails, it refuses to start agents. Protections that can lapse silently (expiring limits, plan changes) are checked on every run instead of trusted.

A future private project needs a paid plan (a GitHub organization on Team) for enforced rulesets. The same exit check is then repeated in that environment.

### Container lifecycle

- One dev container per project. The human starts it with the project's start script (`scripts/up.sh`) when working on the project and stops it afterwards.
- Stories run one at a time on their branch in `/workspace`. V1 has no story worktrees: the read-only paths exist only in `/workspace`, and v1 is not optimised for parallel stories. Parallel stories come with the fresh container per story (backlog item 11).
- The workspace is a clone of the project repo in a Docker volume, not the host clone. The container is recreated on every start, and the volumes persist. The workspace is never deleted automatically: `scripts/up.sh reset-workspace` archives it before replacing it.
- Agents cannot start, stop or control containers. The container has no access to the Docker socket.
- Inside the container, Claude Code runs without per-command permission prompts. Limits come from the container boundary, the network allowlist, read-only mounts, managed settings in the image and role tool restrictions.

### Factory repository

The factory repo follows the same layout conventions as project repos (specs in `specs/`, background in `docs/`), so that the factory can later be developed with the factory without restructuring.

```
skills/              one Agent Skill per role (SKILL.md + references)
agents/              thin role definitions: model, tools, skill
commands/            factory commands such as /factory:run and /factory:context
templates/project/   everything copied into a new project repo
specs/
  factory-v1-spec.md this document
docs/                background and reference material for the factory
scripts/             GitHub setup, step exit checks and helpers (run on the host)
README.md            how to start a new project with the factory
```

### Project repository (created from the template)

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

`.factory/`, `.claude/`, `.github/`, `.devcontainer/` and `CLAUDE.md` are mounted read-only from the owner's host clone of `main`, so no command inside the container can change them. `scripts/up.sh` is not in the container at all. Agents can still create commits that change these paths; the factory definitions guard in step 4 rejects them.

### Configuration (`.factory/config.yaml`)

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

Model choices are initial guesses and will be tuned after the first stories. The config is owned by the human.

### Credentials

- **The agents' GitHub identity is a GitHub App** (`nvipero-factory-orchestrator`), registered under the owner's account and installed only on project repositories, with Contents, Issues and Pull requests read and write and Metadata read. No Workflows, Administration, Checks or Commit statuses permission. A machine user was rejected: it cannot be limited below collaborator rights, needs a classic token for a repository it does not own, and uses up the one free machine account. Everything the factory writes on GitHub appears as the App; the owner's approval is the only one the ruleset accepts.
- **One-hour tokens minted on the host.** The App's private key is a document in the 1Password vault "Agent Factory" and never enters the container. `scripts/up.sh` reads it once per start (one confirmation), signs a JWT with `openssl`, and mints an installation token narrowed to the one repository and those permissions. A refresher started by `up.sh` keeps the key in memory and mints a new token when the current one is 45 minutes old or expires within 15, checking every minute, so a Mac waking from sleep gets a fresh token within a minute. It ends with the container or `up.sh stop`, which removes the token.
- **Delivery:** the token is written to a temporary file and renamed into a host directory outside the clone (`~/.factory-run/<project>/token/`, mode 0700), which is mounted read-only at `/etc/factory/token`. A directory, not the file, is mounted, because a single-file mount keeps the old file after a rename. In the image, a root-owned `gh` wrapper reads the token on every call and puts it only in the real `gh`'s environment; git uses the wrapper as its credential helper for github.com. No credential is in the container's environment or in any process's arguments on the host (key and JWT go through file descriptors and stdin). The rule "never a file on the container's disk" became "never a long-lived credential in the container".
- **The 1Password CLI is never installed in the container.** Access to the vault would expose all other credentials.
- Only containers started by the start script get the token mount. Starting the container any other way, such as from the VS Code UI, skips the token, the workspace setup and the exec guard.
- No other credentials are placed in the container. Claude Code's own credentials are the only exception and are treated as exposed if the container is compromised.
- Anything given to the container can be read by agents. Protection comes from limiting the scope and lifetime of credentials, not from hiding them.
- **Commits** carry the App's bot address (`<id>+<app>[bot]@users.noreply.github.com`) and the role's name as author (`factory <role>`). Neither is authenticated; the `Factory-Role` trailer and the guards are what the checks rely on.

### Labels

- Type: `user-story`, `bug`, `chore`, `trivial`
- State: `ready-for-factory`, `needs-human`, `spec-approved`, `dispute`, `tests-change-approved`
- **Owner-only labels** (`spec-approved`, `tests-change-approved`) count only when the issue's newest `labeled` event for them has the owner's account as actor; GitHub permissions are not per label. The orchestrator and the guards check this, and the `label-audit` workflow removes such a label added by anyone else and fails on label definition changes by anyone but the owner ("trust, but verify").
- **Trusted input** to the agents is text written by the owner that nobody else edited last (GraphQL `author` and `editor`), because the App can edit other accounts' text.
- `tests-change-approved` covers one change: the orchestrator removes it after the reopened test gate approves, and the guard counts the owner's label events against the later changes to approved tests.

## 5. Workflow

| Status | Who acts | Exit condition |
|---|---|---|
| Idea | Human: writes story, sets priority | Label `ready-for-factory` (requires approved project context) |
| Spec | Spec writer, then spec reviewer | Reviewer approves, or questions exist |
| Waiting for human | Human: answers questions, approves spec | Label `spec-approved` |
| Tests | Test writer, then code reviewer checks coverage | Acceptance tests committed |
| Implementation | Implementer and code reviewer, may debate | Reviewer approves and gates pass |
| Dispute | Human: decides | Decision recorded in the issue |
| Preview | Human: evaluates preview against the story | Human approves PR |
| Done | Merged | - |

### Project context (once per project, updated as needed)

1. The researcher researches and interviews the human (`/factory:context`, in the main session): purpose and users are required; domain terms, constraints and non-goals are asked once, and "not decided yet" is a valid answer. It researches before it asks, and asks only what only the human can answer.
2. The researcher writes `docs/product-context.md` and `docs/glossary.md`. Every claim carries a source tag: the human, material the human pointed to, a published standard, official documentation, or best practice that two independent sources agree on. Anything else, including the model's own memory, goes to a separate "not confirmed" section that specs may not rely on.
3. The human corrects and approves the context. Stories are not accepted before this.
4. When a story reveals the context is wrong or incomplete, the context is updated through a PR the human approves.

### Branch model

One branch and one pull request per story. Commits come in order: spec, acceptance tests, implementation. Each role writes only to its own paths (section 4), and CI enforces this. Everything is merged together at the end, so the PR shows the whole chain.

### Naming conventions

Both the factory repo and project repos follow these. Agents follow them too.

- **Commits:** [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/), `type(scope): description`. Types: `feat`, `fix`, `docs`, `chore`, `test`, `refactor`.
- **Branches:** [Conventional Branch 1.1.0](https://conventionalbranch.org/), `<type>/<description>` in lowercase letters, digits and hyphens. `main` takes no prefix.
- **Story branches:** `feat/issue-<n>-<slug>` for a user story, `fix/issue-<n>-<slug>` for a bug, `chore/issue-<n>-<slug>` for a chore.
- **Role commits** carry a `Factory-Role: <role>` git trailer.
- **Enforcement:** instructions until step 4; from step 4 the `guards` check also fails on a non-Conventional commit message or a story branch not named `<type>/issue-<n>-<description>`.

### Story to spec

1. The human writes a story with the issue template: goal, user value, acceptance criteria in plain language, priority.
2. **Understanding check.** The spec writer first writes a "Problem and why" section in its own words, traced to the project context or to the story itself. Where the story settles something the context leaves open, the spec traces it to the story and the ready comment says so; the human may update the context later. If neither supports the problem, the spec writer asks.
3. The spec writer produces `specs/<issue>-<slug>.md`: problem and why, scope, out of scope, testable acceptance criteria, assumptions, open questions.
4. **Research, then ask, then assume.** For an open point that changes the scope or an acceptance criterion, the spec writer first requests research: the orchestrator runs the researcher, which answers in `docs/research/<issue>-<topic>.md` with the same source rules (one research round per task). Only a product decision that only the human can make becomes a question. Everything else is an assumption with a reason. A question is posted to the issue on its own, and the issue gets `needs-human`.
5. The spec reviewer checks ambiguity, missing edge cases, testability, sources and consistency with the project context.
6. **Review loop.** A loop ends only when the reviewer approves the latest version or the work escalates to the human with `dispute`. Fixes are targeted. A change that alters the scope or the acceptance criteria is a rework: it is reviewed in full and restarts the round count, at most `rework_resets` times. `max_rounds` and `escalate_when_no_progress_for` apply per version.
7. When the reviewer approves, the ready comment links the spec and lists its assumptions. The human answers questions in the issue and adds `spec-approved`.

### Spec to merge

1. The test writer turns the approved acceptance criteria into automated acceptance tests, in files named by feature and tagged with the story's criteria (`@issue-<n>-ac-<k>`), and updates existing tests whose behaviour the story changes. The orchestrator runs them: they must fail because the behaviour is missing. The code reviewer checks coverage; the same review loop rules apply.
2. The implementer writes the code on the story branch. The orchestrator checks the paths, runs the unit and acceptance tests itself (its run is the one that counts), and opens a draft PR that closes the issue.
3. The code reviewer reviews against the spec, conventions, architecture boundaries and the security checklist.
4. Implementer and reviewer may debate. On escalation the issue gets `dispute` and a short comment: the disagreement, both positions, what each option costs.
5. **A wrong acceptance test** goes through the orchestrator: the implementer never changes `tests/acceptance/`, and returns a test problem instead. The test writer decides once; after that, the human decides, and adds `tests-change-approved` if the test changes. Any change to approved tests reopens the coverage review.
6. When the reviewer approves and the orchestrator's own test run passes, it writes the PR description, waits for the required checks on GitHub ("trust, but verify"), marks the PR ready, and posts to the issue that the preview appears in the PR's deployments panel.
7. **Feature removal.** A story that removes a feature states the absence as acceptance criteria ("the board shows no Archive button", "tasks stored with the old status still load"). The test writer removes the removed behaviour's tests in the tests phase, before approval, as its own path; the coverage review checks each removal and the guard lists removed tests for "Where to look". After approval, any further change needs `tests-change-approved`.
8. The PR description contains a **"Where to look"** section for the human: restricted-list hits, deviations from the spec, assumptions made, and places where the reviewer is uncertain. The human reads this section and the preview, not the whole diff.
9. The human merges, or comments with changes, which restarts implementation.

## 6. Roles

Each role is an Agent Skill plus a thin role definition stating model, tools and skill.

| Role | Input | Output | Writes to | Must not |
|---|---|---|---|---|
| Orchestrator | Issue | Path choice, role order, test runs, labels, status comment, questions, ready comment, PR and its description | Labels, comments, PR | Write code, specs or tests |
| Researcher | Human interview, research, existing material; research requests | Project context, glossary; research answers | `docs/` | Present guesses or memory as facts |
| Spec writer | Issue, context, research answers, codebase | Spec, research requests, questions | `specs/` | Guess silently, research itself, or write a spec it cannot justify |
| Spec reviewer | Spec, issue, context | Findings | Comments only | Edit files |
| Test writer | Approved spec | Acceptance tests | `tests/acceptance/` | Write production code |
| Implementer | Spec, tests | Code, unit tests | `src/`, `public/`, `tests/unit/`, root project files | Touch acceptance tests, specs or anything outside the story |
| Code reviewer | Tests or PR diff, spec, test results | Findings, approval, "Where to look" | Nothing: the orchestrator posts its output | Edit files |

In v1 the orchestrator is a Claude Code command (`/factory:run <issue>`) run in the main session, which delegates to role subagents. The researcher's interview runs in the main session through `/factory:context`, because subagents cannot ask the human questions; its research-request mode is a subagent. Each producing role commits its own work; the orchestrator pushes.

## 7. Restricted list

Always requires the human: authentication and authorisation changes, data deletion or migration, new external services or paid dependencies, and any change to factory definitions, gates or permissions.

## 8. Deterministic gates (GitHub Actions)

Required checks on every PR (as built in step 4):

- **`guards`** runs `main`'s definition on `pull_request_target` and reads the PR's commits and diff as data, never executing them; event values reach its script only through the environment. It fails on: a commit outside its role's paths or without a parsed `Factory-Role` trailer (spec-only commits excepted); a merge commit that is not a clean merge of `main`; a non-Conventional commit message; a branch not named `<type>/issue-<n>-<description>`; any change to `.factory/`, `.claude/`, `.github/`, `.devcontainer/`, `scripts/` or `CLAUDE.md`; changes to `tests/acceptance/` after the first implementer commit beyond the owner's `tests-change-approved` label events. It lists changed earlier tests and test configuration for "Where to look". The owner's own PRs get only a note.
- **`tests`** runs on `pull_request` with a read-only token and fixed commands (not the project's npm scripts): type check, unit tests, build (`unit-and-build`), and Playwright acceptance tests (`acceptance`).
- **`dependency-review`**: no new dependency with a high-severity vulnerability.
- **CodeQL** (default setup) through the ruleset: no high-severity alert.
- **Secret scanning** with push protection.
- **`label-audit`**: owner-only labels by anyone else are removed.

Test commands cannot be weakened from a PR: the workflow fixes them and the App cannot change workflow files. The gate-change label of earlier revisions is dropped for that reason.

**Preview:** for a PR that is not a draft, `tests` uploads its build; `preview-deploy` runs `main`'s definition on `workflow_run` after `tests` passes, checks without any secret that guards passed on the same commit, then deploys only the build's static files in environment `preview` with the Vercel token, never running PR code there. One preview per PR at `<owner>-<repo>-pr-<n>.vercel.app`, shown in the PR's deployments panel, replaced on each push and removed when the PR closes. The Vercel token is scoped to the one project.

**Production:** `tests` also runs on every push to `main` (without dependency review) and uploads the build; `production-deploy` runs `main`'s definition on `workflow_run` after it passes, only for a push to `main`, only if the commit is still `main`'s head, and deploys the build's static files in environment `production` (deployable from `main` only, same token) to `<repo>.vercel.app`. Deploys queue rather than replace each other. After the deploy it checks that the production address serves the new deployment. Production is public; old deployments are left to Vercel's retention. Before the first merge a placeholder holds the production place, because Vercel makes a project's first deployment production.

## 9. Test project defaults

- TypeScript, React with Vite, Node.js
- Vitest for unit tests, Playwright for acceptance tests
- Vercel for preview and production deployments (Hobby, through the pipeline; no Git integration)

The topic is a Todo-app (owner decision, 2026-10-23): generic and disposable, because the point is to test the factory.

## 10. Build steps

Each step ends with an exit check, and the next starts only after the owner has seen the result.

1. **Foundations.** Factory repo, project template, test project repo, repository protections (including GitHub Actions disabled until step 4), dev container with network allowlist and read-only mounts, start script with token from 1Password and protection checks, scoped token, labels, issue template, Projects board, README. Exit: an agent inside the container cannot modify factory definitions, cannot reach non-allowlisted hosts, cannot see anything outside the project workspace, and cannot push directly to `main`.
2. **Context and spec chain.** Researcher, spec writer with understanding check, spec reviewer, question flow. Exit: approved project context, and one story with an approved spec where at least one question was answered through the issue.
3. **Implementation chain.** Test writer, implementer, code reviewer, `/factory:run` extended to tests and implementation. Exit: the story reaches a PR with passing local tests, a reviewer approval and a "Where to look" section.
4. **Gates, preview and human-only merge.** All gates in section 8, Vercel preview, and a separate GitHub identity for agents (a GitHub App) so that the ruleset can require an approving review from the owner. With a single shared identity this cannot be enforced: merging a PR needs only Contents write, which the agent token must have, and nobody can approve their own PR. Exit: a PR that breaks any gate cannot be merged, every PR marked ready gets a preview link, and the agent identity cannot merge a PR without the owner's approval. Step 4 re-enables GitHub Actions, which is disabled in steps 1 to 3, with restrictions, and updates the `up.sh` check to match. Plan: `docs/plans/step-4.md`; evidence: `docs/verification/step-4.md`.
5. **First full run.** A new story from idea to merge without manual code edits. Exit: definition of done met and problems recorded. Plan: `docs/plans/step-5.md`; evidence: `docs/verification/step-5.md` (v1 done, 2026-10-31).

## 11. Definition of done for v1

- A story written by the human reaches a merged PR without the human editing code.
- The human was asked only at defined points. Each pull request description and long document started with a TL;DR, and each question to the human carried only the question (principle 13).
- The spec's problem and why section is traceable to the approved project context.
- All gates ran and were required for merge.
- No agent modified acceptance tests, factory definitions or gates.
- No agent merged a pull request.
- No agent accessed anything outside its container workspace or allowlisted network.
- Observed problems are written down for the next iteration.

## 12. Known risks

- **Building the factory becomes the project.** Mitigation: strict scope and exit checks per step. V1 has grown during planning, so further additions go to the backlog.
- **Dev container setup takes longer than expected.** It is the biggest single piece of new work in v1, but adding it later would cost more.
- **Subscription limits.** Agent runs share the Team plan quota with the owner's other work.
- **Agent loops.** Mitigation: turn limits and dispute rules.
- **Specs approved without reading.** Mitigation: questions and assumptions are surfaced separately.
- **After the owner approves, the App could technically merge.** Only the deny rule in managed settings prevents it; the owner's approval is the decision that matters, so this is accepted. Before step 4 the agents acted as the owner and could merge without approval; agent commits from then carry the noreply address of an unrelated GitHub account (`factory-agent`) as author and are not rewritten.
- **Roles share the App.** Only commit trailers and the guards tell the roles apart; separate identities per role need separate sandboxes (backlog 9 and 11).
- **Interaction limit expires** after six months. Mitigation: `up.sh` checks it on every run.
- **Copied templates drift** from the factory as it evolves. Accepted in v1. Plugin distribution is in the backlog.

## 13. Open questions for the owner

None open.
