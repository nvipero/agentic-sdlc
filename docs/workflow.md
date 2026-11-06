# Workflow and roles

How a story travels from an issue to a merge, who does what, and when the human is asked.

## Statuses

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

## Labels

- Type: `user-story`, `bug`, `chore`, `trivial`
- State: `ready-for-factory`, `needs-human`, `spec-approved`, `dispute`, `tests-change-approved`
- `spec-approved` and `tests-change-approved` are owner-only ([security](security.md#trusted-input-and-owner-only-labels)).
- `tests-change-approved` covers one change: the orchestrator removes it after the reopened test gate approves, and the guard counts the owner's label events against the later changes to approved tests.

## Project context (once per project, updated as needed)

1. The researcher researches and interviews the human (`/factory:context`, in the main session): purpose and users are required; domain terms, constraints and non-goals are asked once, and "not decided yet" is a valid answer. It researches before it asks, and asks only what only the human can answer.
2. The researcher writes `docs/product-context.md` and `docs/glossary.md`. Every claim carries a source tag: the human, material the human pointed to, a published standard, official documentation, or best practice that two independent sources agree on. Anything else, including the model's own memory, goes to a separate "not confirmed" section that specs may not rely on.
3. The human corrects and approves the context. Stories are not accepted before this.
4. When a story reveals the context is wrong or incomplete, the context is updated through a PR the human approves.

## Branch model

One branch and one pull request per story. Commits come in order: spec, acceptance tests, implementation. Each role writes only to its own paths ([architecture](architecture.md#project-repository-created-from-the-template)), and CI enforces this. Everything is merged together at the end, so the PR shows the whole chain.

## Naming conventions

Both the factory repo and project repos follow these. Agents follow them too.

- **Commits:** [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/), `type(scope): description`. Types: `feat`, `fix`, `docs`, `chore`, `test`, `refactor`.
- **Branches:** [Conventional Branch 1.1.0](https://conventionalbranch.org/), `<type>/<description>` in lowercase letters, digits and hyphens. `main` takes no prefix. `feat/` and `fix/` are allowed short forms.
- **Story branches:** `feat/issue-<n>-<slug>` for a user story, `fix/issue-<n>-<slug>` for a bug, `chore/issue-<n>-<slug>` for a chore.
- **Role commits** carry a `Factory-Role: <role>` git trailer.
- **Enforcement:** in projects, the `guards` check fails on a non-Conventional commit message or a story branch not named `<type>/issue-<n>-<description>`.

## Story to spec

1. The human writes a story with the issue template: goal, user value, acceptance criteria in plain language, priority.
2. **Understanding check.** The spec writer first writes a "Problem and why" section in its own words, traced to the project context or to the story itself. What the app does today comes from `main`'s acceptance tests (the code where no test covers it); earlier specs are history, and a conflict between them and `main`, a newer owner decision or another source becomes a question. Where the story settles something the context leaves open, the spec traces it to the story and the ready comment says so; the human may update the context later. If neither supports the problem, the spec writer asks.
3. The spec writer produces `specs/<issue>-<slug>.md`: problem and why, scope, out of scope, testable acceptance criteria, choices (criteria the spec writer decided itself, each with its basis), assumptions (decisions that change no criterion), open questions.
4. **Research, then ask, then assume.** For an open point that changes the scope or an acceptance criterion, the spec writer first requests research: the orchestrator runs the researcher, which answers in `docs/research/<issue>-<topic>.md` with the same source rules (one research round per issue). A product decision that only the human can make is proposed as a choice when it has a sensible default, and asked otherwise; a contradiction with the project context is always a question. Everything else the spec writer decides as a choice with its basis; an assumption changes no criterion. A question is posted to the issue on its own, and the issue gets `needs-human`.
5. The spec reviewer checks ambiguity, missing edge cases, testability, sources and consistency with the project context.
6. **Review loop.** A loop ends only when the reviewer approves the latest version or the work escalates to the human with `dispute`. Fixes are targeted. A change that alters the scope or the acceptance criteria is a rework: it is reviewed in full and restarts the round count, at most `rework_resets` times. `max_rounds` and `escalate_when_no_progress_for` apply per version. The human's decision on a dispute either changes the work, or keeps it and closes the disputed findings, which the reviewer does not raise again.
7. When the reviewer approves, the ready comment links the spec, lists its choices, and counts its assumptions. The human answers questions in the issue and adds `spec-approved`.

## Spec to merge

1. The test writer turns the approved acceptance criteria into automated acceptance tests, in files named by feature and tagged with the story's criteria (`@issue-<n>-ac-<k>`), and updates existing tests whose behaviour the story changes. The orchestrator runs them: they must fail because the behaviour is missing. The code reviewer checks coverage; the same review loop rules apply.
2. The implementer writes the code on the story branch. The orchestrator checks the paths, runs the unit and acceptance tests itself (its run is the one that counts), and opens a draft PR that closes the issue.
3. The code reviewer reviews against the spec, conventions, architecture boundaries and the security checklist.
4. Implementer and reviewer may debate. On escalation the issue gets `dispute` and a short comment: the disagreement, both positions, what each option costs.
5. **A wrong acceptance test** goes through the orchestrator: the implementer never changes `tests/acceptance/`, and returns a test problem instead. The test writer decides once; after the first implementer commit its change also needs the human's `tests-change-approved` (the guard counts it); after that, the human decides, and adds `tests-change-approved` if the test changes. Any change to approved tests reopens the coverage review.
6. When the reviewer approves and the orchestrator's own test run passes, it writes the PR description, waits for the required checks on GitHub ("trust, but verify"), marks the PR ready, and posts to the issue that the preview appears in the PR's deployments panel, with any choices the spec gained after approval through an owner change request.
7. **Feature removal.** A story that removes a feature states the absence as acceptance criteria ("the board shows no Archive button", "tasks stored with the old status still load"). The spec names the earlier criteria it supersedes. The test writer removes the removed behaviour's tests in the tests phase, before approval, as its own path, and lists the criteria the current app already meets, whose tests may pass before implementation; the coverage review checks each removal and the guard lists the changed and removed test files for "Where to look". After approval, any further change needs `tests-change-approved`.
8. The PR description contains a **"Where to look"** section for the human: restricted-list hits, deviations from the spec, assumptions made, and places where the reviewer is uncertain. The human reads this section and the preview, not the whole diff.
9. The human merges, or requests changes: a change to what the story does goes through the spec writer and the test writer first, a change to the tests through the test writer, anything else to the implementer.

## Roles

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

The orchestrator is a Claude Code command (`/factory:run <issue>`) run in the main session, which delegates to role subagents. The researcher's interview runs in the main session through `/factory:context`, because subagents cannot ask the human questions; its research-request mode is a subagent. Each producing role commits its own work; the orchestrator pushes.

## Restricted list

Always requires the human: authentication and authorisation changes, data deletion or migration, new external services or paid dependencies, and any change to factory definitions, gates or permissions.
