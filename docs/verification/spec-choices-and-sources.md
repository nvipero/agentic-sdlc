# Verification: spec choices and sources

> **TL;DR:** Done. Story C (https://github.com/nvipero/sdlc-pilot/issues/93, deadlines) ran the question path under the App for the first time: the spec writer stopped on the contradiction with the pilot's non-goal, asked one question, and traced the owner's answer in the spec. The new `## Choices` section listed 10 criteria the spec writer decided itself, each tested; the Tab case of the earlier drill became a criterion from the start. Merged and deployed. Not exercised: research. Two problems: many choices and criteria (10 and 18, 54 tests), and a slow first test run (fixed: `actionTimeout`).

Plan: `docs/plans/spec-choices-and-sources.md`. Factory PRs: https://github.com/nvipero/agentic-sdlc/pull/16, https://github.com/nvipero/agentic-sdlc/pull/17; pilot copy: https://github.com/nvipero/sdlc-pilot/pull/92 (merged 2026-11-05).

## Exit check

| What | Result | Evidence |
|---|---|---|
| Question for a contradiction | Exercised | Below |
| Question for a decision with no default | Not planned | |
| Choices | Exercised; 10 lines over 18 criteria, above the plan's 5 | Below, problem 1 |
| Assumptions | Pass (read by me) | 6, none extends, narrows or settles a criterion or an owner decision |
| Tests follow the choices | Pass (read by me) | `task-deadline.spec.ts`: the exact "Due 5 Nov 2026" text (AC-3), "Late" as text (AC-10), Done never late (AC-11), a fixed clock run past midnight (AC-13), click outside and Tab or Shift+Tab out cancel (AC-18) |
| Sources (`main:`) | Pass | `(main: tests/acceptance/task-title-editing.spec.ts)` for the save-failure behaviour; the file has the failing-storage tests |
| Research | Not exercised | WCAG 1.4.1 not requested; "without relying on colour alone" traced to the issue as a visible "Late" text |
| Definition of done | Pass | Every commit on https://github.com/nvipero/sdlc-pilot/pull/94 carries a `Factory-Role` trailer; merged by the owner; required checks passed |

### Spec phase (2026-11-05)

- Issue labeled `user-story` and `ready-for-factory` by the owner at 21:40:35.
- The spec writer returned a question without a spec (status comment: "spec writer: questions, context conflict on deadlines"; no spec commit).
- `question` comment by `nvipero-factory-orchestrator[bot]` at 21:43:50: only the question, three options with a recommendation, and the last line asking for a comment; no assumptions, notes or summary. `needs-human` labeled 21:43:52 by the App.
- Owner's answer at 21:48:35 (comment 6670433467, option A); `needs-human` unlabeled 21:48:49 by the App.
- Spec writer `792fa3c` (one commit, after the answer): the Problem and why traces the non-goal to the owner's answer `(issue: #93, owner comment 6670433467)`; the spec reviewer approved in round 1 with no blocking finding on the non-goal (C5 item 5).
- Ready comment at 21:51:23: "Choices for you to check" (10 lines, matching the spec's `## Choices`), "Assumptions: 6", and the context note from the owner's answer (non-goal to become "Reminders and notifications", glossary "Deadline" and "Late").
- The choices extend the owner's earlier decisions for title editing to the deadline field: a click outside or Tab out cancels (`extends: (issue: #87, owner comment 6548428983)`), the save-failure behaviour (`extends: (main: …)`), keyboard operation. The Tab case of problem 3 in `docs/verification/untested-paths.md` is now a criterion (AC-18) from the start.

### Tests and implementation (2026-11-05)

- `spec-approved` by the owner; test writer `76ee953`: 54 tests for AC-1 to AC-18 in one new file (+775 lines); the tests run 54 failed, 0 passed, every criterion with a failing test; the coverage review approved in round 1.
- Implementer `e3b62e8` (+313 -32); unit 45/45, acceptance 172/172; the implementation review approved in round 1; the required checks passed.
- PR https://github.com/nvipero/sdlc-pilot/pull/94 ready; the issue's ready comment at 22:54:34 says "Choices for you to check: none beyond the approved spec" (C6, no change request).
- Merge: the owner merged https://github.com/nvipero/sdlc-pilot/pull/94 on 2026-11-06 at 09:37:19 (`92ce908`), the issue closed. `production-deploy` run 42196720421 succeeded, and its check "sdlc-pilot.vercel.app serves dpl_9PnvpMsj2aAxnxyCHDqa1p3vwy1W" passed.

## After the story

- Problem 2 fixed in the test writer's configuration rule (`actionTimeout: 5000`; an existing configuration gets it with the next story's tests).
- Owner decisions 2026-11-06, in the spec's backlog (revision 16): pinning `(main:)` citations to the story branch's base commit belongs with item 25; item 26, the researcher writes context updates from the context notes after a merge and the App opens the pull request, the owner merges.
- Context update for story C: the owner runs `/factory:context` with the ready comment's context note.
- Problem 1 stays open: one story is too little to set a limit on choices.

## Problems

| # | Class | What |
|---|---|---|
| 1 | Friction | 10 choices over 18 criteria, against the plan's mitigation of at most 5. Most are proposals or extensions a reader would expect; the list is still long for the owner to check, and every choice is a criterion with tests. Candidate: group choices by decision, or a soft limit in the spec writer |
| 2 | Friction, fixed | The fail-first test run is slow: the Playwright config sets no `actionTimeout`, so every action on a missing element (a click on an edit action that does not exist yet) waits for the whole 30-second test timeout. Seen by the owner in the container on #93 ("every test waits until the timeout"). Candidate: `actionTimeout` of a few seconds in the test writer's config rule; it limits actions only, so a test that waits on purpose with `expect` keeps its own timeout |
