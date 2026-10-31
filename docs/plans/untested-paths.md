# Plan: running the untested paths

Status: approved by the owner on 2026-10-31 (draft 2; draft 1 reviewed by a second model, findings in section 8)
Spec: `specs/factory-v1-spec.md` revision 12, sections 5 and 7; `docs/verification/step-5.md`, problems 4 and 5
Date: 2026-10-31

## TL;DR

> **TL;DR:** First I fix four factory defects that the review found on exactly these paths (each would have stopped or misrouted a run), then two stories you write run the paths that have never run under the App: questions and answers, a research request, your change request on a PR that changes an acceptance criterion, a feature removal, and, made likely by a temporary review-round limit of 1, a dispute, its decision and a resumed run. A test problem from the implementer cannot be caused without a hand edit; it is recorded only if it happens. The first merge also finishes the two open checks of the `main` deployment.

- **Why:** step 5 lesson: a clean run proves less than it looks. These paths were written but never ran; the review shows they would have failed (owner decision 2026-10-31: this is next).
- **Where I need you:** approve this plan; merge the factory PR and two pilot PRs; write two stories; answer questions; approve two specs; one change request through a PR review; decide disputes if they come; merge the two story PRs.
- **Most likely reason this slips:** the agents take the easy way (no questions, no research, no blocking findings), or another defect turns up mid-run. A path that does not happen is recorded as not exercised; I do not chase it with more stories without asking you.

## 1. Basis

- `commands/run.md` sections 4 (answer, decision, change request), 5 (research, questions), 8 (test problem), 10 (commit check, review loop); spec section 5 items 4, 5, 7 and 9.
- Paths never run under the App (step 3, 4 and 5 verification): question and answer, research request, test problem, dispute and decision, resumed run with open findings, owner change request, feature-removal story.
- The pilot today: add a task, move it with buttons or drag and drop, remove it with Undo, a message when tasks cannot be saved. `docs/product-context.md` lists editing a task as an open question.
- Checked 2026-10-31 by the reviewer: the WAI-ARIA Authoring Practices have no pattern for editing text in place, so story A names WCAG 2.2 success criterion 2.1.1 Keyboard instead (W3C sources are on GitHub, which the researcher reaches).
- Found while planning, out of scope: `light_path` (label `trivial`) is in `config.yaml` and the spec's issue types, but `run.md` has no light path. Recorded as a problem.

## 2. Factory fixes before the runs

Each is a defect on a path these stories run; all verified against the code. One factory PR, reviewed by a second model, then copied to the pilot.

| # | Defect | Fix |
|---|---|---|
| F1 | **Research is lost after questions.** The spec writer gets the research file only in `research-done` (`skills/spec-writer/SKILL.md:17`) and does not read `docs/research/` itself (`:19`). A story that needs research and questions asks after research; the `answer` run then writes the spec without the research, or requests a second round | The orchestrator passes the issue's research files (`docs/research/<n>-*`) on every spec-writer call; the skill reads them, and with a file present a new research request counts as a question |
| F2 | **An owner change request that changes an acceptance criterion never reaches the spec** (`run.md:99` routes only to the test writer or implementer). The reopened `tests` gate's reviewer checks tests against the unchanged spec and blocks them; the spec on `main` ends up false | A request that changes what the story does goes first to the spec writer (`answer` with the comments), then the test writer `fix`; the owner's request is passed to the code reviewer at the reopened gate. The trusted-comment queries get the timestamps that "newer than the ready comment" needs (`run.md:61`) |
| F3 | **A decision that keeps the work dead-ends.** "Decision" always calls the writer (`run.md:90`); with nothing to change it makes no commit, and the commit check (`:233`) stops the run. The restarted reviewer is not told the decision and may raise the same finding again | When the decision keeps the work, no writer call: the decision is recorded as the response, those findings are closed by the owner, and the reviewer gets the decision. A writer `fix` that disagrees with every finding may end without a commit |
| F4 | **A first-time test problem fails `guards`.** The implementer's work-in-progress commit comes first, so the test writer's fix is a test change after implementation started, which `guards` allows only with an owner `tests-change-approved` event (`guards.sh:116`, `:153`); `run.md:203` does not ask for one | The orchestrator asks the owner for `tests-change-approved` before the test writer's fix, as it does for a change request. Spec section 5 item 5 says so |
| F5 | Small, on the same paths: a removal story contradicts an earlier spec by design, and the spec reviewer blocks any contradiction (`skills/spec-reviewer/SKILL.md:26`); "the tests must fail" (`run.md:151`) is false for absence criteria; the dispute comment does not tell the owner to remove `dispute` (`run.md:49`), which the next run requires (`:71`); spec section 5 item 7 says `guards` lists removed tests, but it lists files | The spec writer names superseded criteria in scope and the reviewer accepts a named supersession; at least one test per changed criterion must fail and the test writer names those that already pass; the dispute comment's last line says to remove `dispute`; the spec text corrected |

## 3. Decisions

| # | Decision | Reason |
|---|---|---|
| 1 | **Two stories, one at a time:** story A (a new feature with open decisions and your change request) and story B (a feature removal) | Every path except the test problem fits into two stories |
| 2 | **Temporary `disputes.max_rounds: 1`** in the pilot's `.factory/config.yaml`, in the pilot PR that brings the fixes, restored in a later pilot PR | With 1, any gate whose first review has a blocking finding escalates before the writer answers, so a dispute is likely. Assumption: acceptable that such a dispute comment shows the reviewer's position only, and that there may be more than one dispute; each costs you a comment and me a run |
| 3 | **No forced test problem.** It needs a wrong acceptance test, which only a hand edit could guarantee | Recorded if it happens |
| 4 | **Your change request changes an acceptance criterion,** through a PR review (**Request changes**), and you add `tests-change-approved` at the same time | Runs F2's route: PR back to draft, spec writer, test writer, the label in `guards`, the reopened `tests` gate, ready again. The label with the review saves a stop |
| 5 | **Evidence from GitHub's records,** corroborated beyond the App's own status comment: label events with actors, comment authors, review states, PR timeline events (`convert_to_draft`, `ready_for_review`) with actors, commits per role and their order | Principle 15 |
| 6 | **Defects found mid-run are fixed in the factory,** copied through a pilot PR you merge, and the run resumes; nothing is edited by hand in the pilot | Same rule as step 5 |
| 7 | **The `main` deployment's two open checks ride on story A:** its PR's preview as before, and after its merge I re-run `tests` run 41230740166 (`push`, `f1557a8`, attempt 1) with "Re-run all jobs" through your `gh` login on the host: `production-deploy` must skip, production unchanged | No separate probe PR |

## 4. The stories

Suggestions; you write the issues in your own words, with the labels `user-story` and `ready-for-factory`. Never touch `needs-human` or `dispute` except as asked: the run reads them.

**Story A: edit a task's title.** "As the user I want to change a task's title, so that I can fix a typo without removing and re-adding the task. Editing must work with the keyboard alone (WCAG 2.2, 2.1.1 Keyboard)." (→ research.) Leave out on purpose what happens to an empty title, whether Escape cancels, and whether editing is allowed in every status (→ questions).

**Story B: remove Undo after removing a task.** "As the user I no longer want the Undo button after removing a task; removing is final." (→ feature removal: absence criteria, the earlier spec's Undo criteria named as superseded, the test writer removes the Undo tests before approval.)

## 5. The runs

| # | Who | What |
|---|---|---|
| 1 | Me | Factory PR with F1–F5, second-model review of its diff |
| 2 | You | Merge it; I open the pilot PR (your `gh` login, as `.factory/` changes require) with the fixes and `max_rounds: 1`; you merge it and pull the host clone |
| 3 | You | Story A; I run `/factory:run` and log every path as it happens; you answer questions in full sentences and approve the spec with `spec-approved` |
| 4 | You | When the PR is ready: **Request changes** changing one criterion (for example "Escape keeps the edit instead of cancelling") and add `tests-change-approved`; after it is ready again, approve and merge |
| 5 | Me | The deployment's two checks (decision 7) |
| 6 | You, me | Pull the host clone; story B the same way, without a change request |
| 7 | Me | Pilot PR restoring `max_rounds: 4`; you merge it |
| 8 | Me | `docs/verification/untested-paths.md`, problems list, memory, brain note proposal |

A dispute stops the run: you decide with a comment and remove `dispute`; the next `/factory:run` is the resumed run with open findings.

## 6. Exit check

| Path | Evidence |
|---|---|
| Question and answer | A `question` comment by the App with only the questions; `needs-human` labeled by the App, then unlabeled by the App after your answer; the spec commit after it applies the answers |
| Research request | The researcher's commit (`Factory-Role: researcher`) with a file in `docs/research/` that starts with a TL;DR and tags its sources; the spec's sources citing that file, also after the questions (F1) |
| Owner change request | Your `CHANGES_REQUESTED` review; `convert_to_draft` by the App; your `tests-change-approved` event; a spec commit, then a test writer commit, after the review; `guards` passing; the label unlabeled by the App after the reopened gate approves; `ready_for_review` by the App |
| Feature removal | Spec with absence criteria and the superseded criteria named; the test writer's commit removing the Undo tests, before the first implementer commit; `guards`' "existing test files changed or removed" lines |
| Dispute, decision, resumed run | If it happens: `dispute` labeled by the App, the dispute comment, your decision comment, `dispute` unlabeled by you, and the run continuing to a merge; for a decision that keeps the work, no writer commit and the findings closed (F3). If not: recorded as not exercised |
| Test problem | If it happens: the owner asked for the label before the fix (F4), the test writer's commit after an implementer commit, `guards` passing. If not: recorded as not exercised |
| Definition of done for both stories | As in step 5: no human code commits, only you merged, all gates required and passing |

## 7. Where I need you

- **You:** approve this plan, including the assumption in decision 2; the steps marked "You" in section 5.
- **I do on my own:** the factory fixes and their review, the pilot PRs, the runs, logging, further fixes through PRs, the deployment checks, the verification document.

## 8. Second-model review of draft 1

Three blocking findings and eleven non-blocking, all verified against the code before taking them in.
- **Blocking, now F1–F3:** research lost after questions; an acceptance-criterion change request never reaching the spec; a decision that keeps the work dead-ending on the commit check.
- **Non-blocking, taken in:** the first-time test problem failing `guards` (F4); the removal story against the spec reviewer, "the tests must fail", the dispute label, `guards` listing files (F5); evidence that only the App's status comment would show, or that is never posted (section 6); the label with the review, the fixes and `max_rounds` in one pilot PR, labels to use, pulling the host clone, the re-run through your login (sections 4, 5); the spec section reference; WAI-ARIA has no inline-editing pattern (story A names WCAG 2.1.1).
- **Considered, not taken:** wording the change request as behaviour so that it might route through a test problem and a dispute in one go. It depends on the orchestrator's judgment, and F2 makes the plain route correct.
