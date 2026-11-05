# Plan: spec choices and sources

Status: approved by the owner on 2026-11-05 (draft 2; draft 1 reviewed by a second model, findings in section 9)
Spec: `specs/factory-v1-spec.md` revision 14, principles 1, 2, 10 and 12; `docs/verification/untested-paths.md`, problems 1 to 3
Date: 2026-11-05

## TL;DR

> **TL;DR:** Three changes to the spec writer and spec reviewer. (1) When the spec writer extends, narrows or settles a criterion or an owner decision on its own, that becomes an acceptance criterion, so it is tested, and the spec lists it under a new "Choices" section with its basis; the ready comment shows the choices for you to check before `spec-approved`. (2) What the app does today comes from `main`'s acceptance tests (code only where no test covers it); earlier specs are history, and a conflict the spec writer cannot settle from a source becomes a question. (3) For a product decision with a sensible default, the spec writer may propose it as a choice instead of asking. One pilot story (deadlines, which contradicts a non-goal) runs the question path and the choices. The implementation-phase route for unspecified behaviour goes to the backlog.

- **Why:** owner decisions 2026-11-05: keep useful inferences but test them; do not bind the spec writer to old specs; escalate conflicts it cannot settle; a proposal the owner can comment on before approval is as good as a question.
- **Where I need you:** approve this plan; merge the factory PR and the pilot PR; write one story; answer the spec writer's question; check the choices and approve the spec; merge the story PR.
- **Most likely reason this slips:** the spec writer turns too much into choices and criteria, and the ready comment and the test suite grow. Mitigation: the rule covers only extending, narrowing or settling a criterion or an owner decision; the drill counts choices and records more than 5 as a problem.

## 1. Basis

- **Problem 3 (Tab case, story A):** the owner decided "a click outside cancels" (AC-15); the spec writer extended it to leaving with Tab as an assumption (pilot `specs/87-edit-task-title.md`). Assumptions have no tests. The spec reviewer's item 7 already says an assumption that changes a criterion should have been a question, and it missed it; the rule forces a question where a proposal would do.
- **Problem 2:** the spec left a choice untestable (a click outside saves or cancels); the owner settled it with a change request. The same rule catches it.
- **Problem 1 (no questions in two stories):** the spec writer settled every open point from earlier specs or from the story's words. Earlier specs may be stale; `main`'s acceptance tests are what the app does today.
- **Current text:** `skills/spec-writer/SKILL.md` sections 1 to 3 and "Sources you may rely on"; `skills/spec-reviewer/SKILL.md` checklist items 2, 5 and 7; `commands/run.md` section 4 (change request), section 6 (the ready comment lists every assumption) and the pull request's ready comment. The spec writer has read access to the whole working tree but runs `git` only on its own spec file (`agents/spec-writer.md`).
- **The pilot's non-goals** include "Reminders, notifications and deadlines (owner)" (`docs/product-context.md`). The spec writer's rule for a story that contradicts the context is unconditional: no spec, one question (`skills/spec-writer/SKILL.md` section 1).

## 2. Changes

One factory PR, its diff reviewed by a second model, then copied to the pilot with the next `.factory` copy (which also brings https://github.com/nvipero/agentic-sdlc/pull/16).

| # | Where | Change |
|---|---|---|
| C1 | spec writer, sections 2 and 3 | **Choices are criteria.** When the spec writer extends, narrows or settles a criterion or an owner decision on its own (for example the owner's "click outside cancels" applied to Tab), it writes an acceptance criterion and lists it in a new spec section `## Choices`: the AC id and its basis, one line. A basis is a source it may rely on, the owner decision it extends (`extends: issue #n, owner comment <id>`), or `proposal: <why this is a sensible default>`. **Assumptions** keep the rest: points that change no criterion (unchanged rule, section 3) |
| C2 | spec writer, section 3 | **Propose or ask.** For a product decision only the owner can make: propose (a choice with basis `proposal`) when one option is a sensible default the owner can change before approval at little cost; ask when no option is, or when the options change the story's size or direction. A story that contradicts the context is always a question, whatever the story says (section 1, unchanged) |
| C3 | spec writer, sources and section 1 | **Current behaviour from `main`.** New source tag `(main: <path>)` for what the app does today, read from the story branch's working tree (`main` plus the spec commits): `tests/acceptance/` first, code only where no test covers the behaviour, and never as an implementation detail in a criterion. Earlier specs are history: when one disagrees with `main` or with a newer owner decision and the story depends on it, it is a question, unless a later spec names it as superseded. Two sources it may rely on that disagree (research against an earlier owner decision) are a question too. **An owner's answer to a contradiction** is traced as `(issue: #n, owner comment <id>)` and reported as `context_update` |
| C4 | spec writer, section 3 | **Unconfirmed research that would change behaviour** becomes a choice with basis `proposal (research unconfirmed: <reason>)`; unconfirmed research that changes no criterion stays an assumption, as today |
| C5 | spec reviewer, checklist | Item 7: an assumption that extends, narrows or settles a criterion or an owner decision is a blocking finding (no test checks it); each choice has a stated basis, and a source or owner-decision basis says what the spec claims; whether the owner would agree with a proposal is not the reviewer's call. Non-blocking: a question a sensible default would have settled. Item 2 accepts `(main: <path>)` and checks the path. Item 5: a contradiction the owner resolved in a trusted comment on this issue is not a finding; a claim about current behaviour traced only to an earlier spec where `main` differs is |
| C6 | `commands/run.md` | The spec's ready comment lists **"Choices for you to check"** read from the spec's `## Choices` section (one line each), and the assumptions as a count with the spec link. On an owner change request after approval (section 4), the spec writer's new choices, if any, go into the pull request's ready comment, since that route has no spec ready comment |
| C7 | spec | Revision 15: the spec writer, the spec's sections, the ready comments; backlog items 24 and 25 (section 4) |

## 3. Decisions

| # | Decision | Reason |
|---|---|---|
| 1 | **No new role** | Each change is a rule inside an existing role; the orchestrator only shows a list it reads from the spec |
| 2 | **Choices live in the spec, not in a return field** | The reviewer reads the spec, a resumed run reads the spec, and nothing depends on a session's memory (principle 1) |
| 3 | **The reviewer blocks only the problem 2 and 3 class,** not every behavioural assumption | Spec 87 had 15 assumptions; turning all behavioural ones into criteria would grow the test suite and the ready comment without catching more of what went wrong |
| 4 | **Choices reach you in the ready comment, not as questions** | You read the spec before `spec-approved` anyway (owner, 2026-11-05); a question stops the run for each |
| 5 | **`max_rounds` stays at 4** in the drill | The paths this plan needs are the spec writer's, not disputes |
| 6 | **Evidence from GitHub's records,** as before | Principle 15 |

## 4. Out of scope, to the backlog

- **Item 24, unspecified behaviour in the implementation.** When the implementer adds behaviour no criterion covers, it returns it to the orchestrator instead of the reviewer only flagging scope creep. The orchestrator either has the test writer test it, if it fits the approved spec (needs `tests-change-approved`), or removes it and opens a follow-up story draft without `ready-for-factory`, written by the spec writer; both listed in the pull request. Needs a new orchestrator action (opening an issue) and a change to the code reviewer's scope rule (owner, 2026-11-05).
- **Item 25, a spec that `main` overtakes during a story.** Another merge can change behaviour the spec relies on before the story merges. Rare while stories run one at a time; it matters with parallel stories (item 11).

## 5. The story

**Story C: deadlines.** Suggestion, in your own words, labels `user-story` and `ready-for-factory`: "As the user I want to give a task a deadline, so that I see which tasks are late. A late task must be recognisable without relying on colour alone." The word "deadline" matches the non-goal on purpose. Leave open how the date is entered and shown, and what marks a late task.

What it should cause:
- **A question** (the contradiction rule): deadlines are a non-goal. You answer whether the story holds, for example "Deadlines without reminders are fine; update the context." If no question comes, I stop the run before the spec is approved, record it, and we decide together.
- **Research, possibly:** "without relying on colour alone" points to WCAG 1.4.1. The researcher could not reach some W3C pages before; if it fails, C4 turns the point into a choice.
- **Choices:** date format, where the date shows, what marks a late task.
- **`(main: …)` sources:** the task card and storage as tested today.

## 6. The runs

| # | Who | What |
|---|---|---|
| 1 | Me | Factory PR with C1–C7, second-model review of its diff |
| 2 | You | Merge it; I open the pilot PR (your `gh` login) copying `.factory`; you merge it and pull the host clone before the next step |
| 3 | You | Story C; I run `/factory:run` and log; you answer the question in a comment |
| 4 | You | Check the choices; comment to change any, or add `spec-approved` |
| 5 | You | Review and merge the story PR |
| 6 | Me | `docs/verification/spec-choices-and-sources.md`, memory, brain note proposal |

## 7. Exit check

| What | Evidence |
|---|---|
| Question for a contradiction | A `question` comment by the App with only the question; `needs-human` labeled and unlabeled by the App; the spec commit after your answer traces it to your comment; the `context_update` in the ready comment's context notes; no blocking finding on the non-goal |
| Question for a decision with no default | Not planned; recorded as exercised only if it happens |
| Choices | The spec's `## Choices` section, each line an existing AC with a basis; the ready comment's list matches it; the number recorded, more than 5 recorded as a problem |
| Assumptions | None extends, narrows or settles a criterion or an owner decision (read by me, after the reviewer) |
| Tests follow the choices | For each choice, its test checks the chosen behaviour itself, not only that something exists (read by me) |
| Sources | At least one `(main: <path>)` pointing to `tests/acceptance/`, and the path says what the spec claims |
| Research | If requested: the researcher's file, and the spec citing it or a choice with `research unconfirmed`; if not, recorded as not exercised |
| Definition of done | As before: no human code commits, only you merged, all gates required and passing |

## 8. Where I need you

- **You:** approve this plan; the steps marked "You" in section 6.
- **I do on my own:** the factory changes and their review, the pilot PR, the run and its log, fixes through PRs, the verification document.

## 9. Second-model review of draft 1

Five blocking findings and eight non-blocking, verified against the files before taking them in.
- **Blocking, taken in:** a proposal had no allowed basis, so the reviewer would block every one (C1 `proposal` basis); `choices` as a return field was invisible to the reviewer and lost on a resumed run (now a spec section, decision 2); after your answer, the reviewer would still block the contradiction with the non-goal (C3, C5 item 5); the draft's wording let the spec writer settle the contradiction from the issue, as stories A and B did (C2 keeps the unconditional rule, the story says "deadline", section 5 says what happens without a question); unconfirmed research that would change behaviour had nowhere to go (C4).
- **Non-blocking, taken in:** the reviewer rule narrowed to the problem 2 and 3 class, with a number in the exit check (decision 3); a change request after approval carries its choices to the pull request (C6); the default-less question path stated as not planned; the "tagged test per choice" row replaced, since the test gate already requires a tag per criterion; assumptions as a count in the ready comment; `(main:)` prefers acceptance tests and means the story branch's working tree; a reviewer note for a question a default would have settled; the host clone pulled before the run (done 2026-11-05, `max_rounds: 4`).
