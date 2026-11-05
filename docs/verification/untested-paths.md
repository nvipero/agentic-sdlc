# Verification: running the untested paths

> **TL;DR:** Done. Two stories (sdlc-pilot #87 and #89) ran under the App for the first time: five disputes with the owner's decisions and resumed runs, a decision that keeps the work (F3), a spec change request before approval, the owner's change request on a PR that changed the spec (F2), and a feature removal (F5); both merged and deployed to production. Not exercised: questions, research and a test problem, because the spec writer settled every open point from the issue or earlier specs, and no wrong test came up. The run found one new defect class (problem 4: retrying assertions pass absence criteria against the old feature).

Plan: `docs/plans/untested-paths.md`. Factory fixes: https://github.com/nvipero/agentic-sdlc/pull/11; pilot copy with `max_rounds: 1`: https://github.com/nvipero/sdlc-pilot/pull/86 (merged 2026-10-31).

## Paths

| Path | Story | Result | Evidence |
|---|---|---|---|
| Dispute, decision, resumed run | A (#87) spec, tests and `impl` gates; B (#89) spec and tests gates | Exercised five times | Below |
| Decision that keeps the work (F3) | A (#87), `impl` gate | Exercised | Below |
| Question and answer | A, B | Not exercised | Problem 1 |
| Research request | A, B | Not exercised | Problem 1 |
| Spec change request before approval | A (#87) | Exercised | Below |
| Owner change request on the PR (F2) | A (#87), PR https://github.com/nvipero/sdlc-pilot/pull/88 | Exercised, through a third dispute | Below |
| Feature removal (F5) | B (#89), PR https://github.com/nvipero/sdlc-pilot/pull/90 | Exercised | Below |
| Test problem (F4) | | Not exercised | No implementer claimed a wrong test (plan decision 3) |

### Story A, spec phase (2026-10-31)

- Spec writer `840bbae` (`Factory-Role: spec-writer`, author `factory spec-writer`); the spec reviewer's round 1: changes, 1 blocking (R1-1, AC-12 not testable: no named save control).
- `max_rounds: 1` passed: `dispute` labeled 19:41:39 by `nvipero-factory-orchestrator[bot]`; the dispute comment (6548233875) by the App gives both positions, two options with their cost, the reviewer's three non-blocking notes, and the last line to remove `dispute` (F5).
- Owner's decision 6548352468 ("1. Require a named Save action"), `dispute` unlabeled 19:52:55 by the owner.
- Resumed run: `decision=6548352468` in the state; spec writer `313436e` "apply owner answers"; the spec gate restarted (`spec=1/0/313436e`) and the reviewer approved in round 1; ready comment 6548372372.
- **No question and no research request.** The spec writer resolved the deliberately open points as assumptions traced to earlier specs: empty and whitespace titles as in spec 28 AC-5 and AC-6, Escape to cancel as a way out for keyboard users, WCAG 2.1.1 traced to the issue. Each assumption has a reason, and the reviewer accepted them. The story design, not the factory, failed here: the pilot's earlier specs already answered what the story left open.

- Spec change request: owner comment at 19:59:57 ("Clicking outside the text field while editing cancels the edit, like Escape."); spec writer `2888e6c`, new AC-15; ready comment again at 20:01:32; `spec-approved` labeled 20:04:43 by the owner.

### Story A, tests and implementation (2026-10-31)

- Test writer `b1d5722` (34 tests, all failing). The code reviewer's round 1 blocked on two findings: R1-1, the AC-6 checks collapse whitespace, so an untrimmed title would pass; R1-2, AC-3 and AC-4 read the position from accessible names and break on quotes.
- `max_rounds: 1` passed: `dispute` labeled 20:41:21 by `nvipero-factory-orchestrator[bot]`, the dispute comment at 20:41:19.
- Owner's decision at 21:11:02 ("1. Fix both, and extend the titles() helper as R1-3 suggests"), `dispute` unlabeled 21:11:17 by the owner.
- Resumed run: test writer `a1098f2` applied the decision; implementer `c7107e9`; PR https://github.com/nvipero/sdlc-pilot/pull/88 ready at 21:48:44, all checks passing (`guards`, `acceptance`, `unit-and-build`, `dependency-review`, CodeQL).

### Story A, owner change request on the PR (2026-10-31)

- Owner's `tests-change-approved` labeled 21:59:01; review `CHANGES_REQUESTED` 21:59:56 ("Moving keyboard focus out of the edit with Tab or Shift+Tab must cancel the edit like Escape. Make it an acceptance criterion with tests, not an assumption."). The owner's earlier `APPROVED` (21:55:47) stays in the history.
- `convert_to_draft` 22:01:12 by `nvipero-factory-orchestrator[bot]`; spec writer `7d5e86c` (new AC-16, AC-11 narrowed, the review cited as source), then test writer `93712b5`; no spec ready comment, as F2 intends.
- `tests-change-approved` unlabeled 22:04:42 by the App after the reopened tests gate approved; `guards` passing on `93712b5`.
- The implementation already passed the new tests (no implementer commit). The restarted `impl` gate's round 1 blocked (R1-1: Tab out of the page into the browser's own controls leaves the edit open), and `max_rounds: 1` escalated: `dispute` labeled 22:07:32 by the App.
- Owner's decision 6549868436 at 22:16:56 ("2. Keep the code as it is. ..."), `dispute` unlabeled 22:17:00 by the owner.
- Resumed run (F3): no writer call and no new commit (the head stays `93712b5`); the chain records "owner: decided implementation dispute: keep the code (6549868436)", and the restarted reviewer approved in round 1 with the decision in hand, repeating only the non-blocking note. `ready_for_review` 22:18:17 by the App, ready comment 22:18:19; state `impl=1/0/93712b5 decision=6549868436 request=5725128765`; all checks passing.
- Merge: PR https://github.com/nvipero/sdlc-pilot/pull/88 merged by the owner at 22:21:44 (`25a974d`), the issue closed. `production-deploy` run 41247992048 succeeded; deployment 7465229620 (`25a974d`) to https://sdlc-pilot.vercel.app, and the job's check "sdlc-pilot.vercel.app serves dpl_7RUFPJVJ6PUpX5FLsbjYKmXtnxAN" passed. The re-run check of plan decision 7 was already done in `docs/verification/main-deploy.md`.

### Story B, spec phase (2026-11-02)

- Spec writer `172fb93`: absence criteria (AC-2: no Undo and no message after removal) and the superseded criteria named in scope ("Supersedes `specs/29-remove-task-no-longer-needed.md` AC-4, AC-5, AC-6, AC-8 to AC-12 ..."), as F5 intends; the spec reviewer did not block on the supersession.
- **No question again.** The issue was written to leave open whether a confirmation replaces Undo (the owner chose Undo over a confirmation for #29); the spec writer settled it from the issue's "removed at once" and put a confirmation out of scope.
- The spec reviewer's round 1 blocked on R1-1 (a Primer guideline tagged `standard` instead of `docs`, and the next-then-previous focus order not stated as the spec's own choice); `dispute` labeled 09:31:37 by the App.
- Owner's decision at 09:37:34 (option 1 plus two non-blocking points), `dispute` unlabeled 09:37:44 by the owner; the resumed run's spec was approved by the reviewer and the ready comment posted at 09:39:14 (AC-2 and AC-4 made testable: 10 seconds, 100 ms).

### Story B, tests phase (2026-11-03)

- `spec-approved` labeled 08:25:15 by the owner. Test writer `c14c7f1` rewrote `tests/acceptance/task-removal.spec.ts` (+131 -127), removing the Undo tests, before any implementer commit.
- The code reviewer's round 1 blocked on two findings: R1-1, the absence checks use retrying `toHaveCount(0)`, which waits out the current app's 5-second message, so an AC-2 test can pass against the old behaviour; R1-2, retrying `toBeFocused()` waits for the old delayed focus move to the heading. `dispute` labeled 08:53:15 by the App. The finding is a real class: retrying assertions make absence criteria pass against the feature being removed.
- Owner's decision 6634890668 (option 1); test writer `ffcd034` (absence and focus checks non-retrying); the tests run: 14 failing, 10 passing (AC-1, AC-4, AC-5 already pass, as the feature removal expects); the reviewer approved in round 1.
- Implementer `b656b9a` (+57 -97 in 4 files), 118/118 acceptance tests; the implementation gate approved in round 1. Draft PR https://github.com/nvipero/sdlc-pilot/pull/90; `guards` compares `25a974d...b656b9a`, where `tests/acceptance/task-removal.spec.ts` is modified (listed in its step summary).
- The run stopped with the PR in draft: required checks were still pending after 20 minutes. The jobs ran 15:56 to 15:58, but the runs were marked complete only at 16:17 to 16:20, during a GitHub incident ("Incident with Actions and Pages", resolved 16:05:31Z, githubstatus.com). The orchestrator's stop was correct.
- Resumed run: the PR marked ready (`ready_for_review` 2026-11-05 06:40:29 by the App). The owner approved and merged it at 20:35:04 (`960bfde`), the issue closed. `production-deploy` run 42104917569 succeeded; deployment 7584722821 (`960bfde`), and the check "sdlc-pilot.vercel.app serves dpl_4zR92ZCwsHN83E2zCAaSxkUHCbLX" passed.

## After the drill

- `max_rounds: 4` restored: https://github.com/nvipero/sdlc-pilot/pull/91.
- Definition of done for both stories: no human commits on either branch (every commit carries a `Factory-Role` trailer), only the owner merged, all required checks passed.
- Next, as proposals for the owner: the test-writer skill rule from problem 4; a story built around a decision no spec or standard answers, if questions and research still need a run (problem 1); problems 2 and 3 as a spec-reviewer check that every behaviour in the assumptions either has a criterion or is stated as out of scope.

## Problems

| # | Class | What |
|---|---|---|
| 1 | Idea | Stories designed to cause questions do not reliably cause them once earlier specs cover the area; a question needs a decision no spec or standard touches |
| 2 | Friction | The spec left an untestable choice to the implementation (clicking outside the field either saves or cancels); the reviewer did not flag it. The owner settled it with a spec change request |
| 3 | Friction | The spec writer turned the owner's AC-15 (a click outside cancels) into an assumption for leaving with Tab, too, with no criterion and so no test; the spec reviewer accepted it. Behaviour the owner may care about stays untested |
| 4 | Defect | The test writer's absence checks used Playwright's retrying assertions, which wait out a timed message (5 s) and so pass against the feature being removed; caught by the code reviewer, not by the test writer's own fail-first check. Candidate for the test-writer skill: absence criteria are checked without retry, after a positive wait for the state change |
