# Assist plugin trial

Plan: [issue #69](https://github.com/nvipero/agentic-sdlc/issues/69#issuecomment-6820018643), approved 2026-11-12. The runs are in the owner's client repositories, so this record is a redacted summary: no client, product, code, data or task content.

## Task 1 (2026-11-12)

A story in an existing Python and TypeScript repository with its own `CLAUDE.md`, `CLAUDE.local.md`, `.claude/` skills and hooks, and a pull-request review skill of its own. The story started with a measurement on real data, so it exercised the "measure first" step.

| Measure | Result |
|---|---|
| Size | 6 files, 10 commits on the task branch |
| Phases | baseline, plan, measurement, owner approval, implementation, review, done |
| Implementer runs | 4 (the first run and 3 fixes; the limit) |
| Plan review | none by the plugin; the owner had a fresh agent review the plan, which added two safeguards to the criteria |
| Plugin review | 1 round, approve, 1 non-blocking finding |
| Owner interventions | 4: plan approval, accepting a known loss the reviewer flagged against a criterion, and two decisions on findings from the repository's own pull-request review |
| After the plugin | the repository's own pull-request review ran 3 rounds; one finding was fixed, others were recorded as follow-ups |
| Outcome | pull request merged by the owner; story done |
| Wall-clock | not measurable: `State` recorded dates only, not times |

**Owner's verdict:** the result was good and the plugin is worth using further. Not compared directly, because the same task was not done with plain prompting.

**Owner's observations, and what changed in this pull request:**

1. The plan reached the owner without a review. → The reviewer now has a `plan` gate that runs before the owner sees the plan.
2. A long implementer run (a local model run) gave no sign of where it was. → The implementer appends a line per step to a `## Progress` section of the plan file, to follow with `tail -f`.
3. Every `git push` asked for approval, from the ask rule the setup added. The owner does not want that: changes reach the default branch only through a pull request. → The ask rule is dropped from the setup, and the command pushes the task branch itself, never the default branch.

## Not yet tried

- A repository without tests (the "no tests" question in the plan).
- A second repository. The next tasks are in the same one.
