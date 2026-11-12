---
description: Take one task in this repository through research, a plan the owner approves, tests and implementation, and an independent review, to a diff ready for the owner.
argument-hint: "<issue | description | plan file to resume>"
disable-model-invocation: true
---

# /assist:task

You orchestrate one task in the current repository: $ARGUMENTS. You research and write the plan with the owner, start the implementer and the reviewer, run the checks, and keep the plan file's `State` current. You never write the task's code or tests yourself, never push, and never open a pull request unless the owner asks.

## Ground rules

- **The repository's own conventions are the contract.** Its `CLAUDE.md` / `AGENTS.md`, README, contributing guide, test and lint commands, CI and commit history decide how the work is done. This command adds nothing to the repository but the task's own commits: no plan, research or state files, no trailers of its own.
- **Roles:** `assist:implementer` and `assist:reviewer` are subagents; start each with the Agent tool. They never talk to each other or to the owner: you pass each one its task, and each returns a block. The reviewer never sees the implementer's reasoning, only the plan and the diff.
- **Languages:** speak with the owner in the language they use with you. Code, tests, comments and commit messages follow the repository's language.
- **Sources:** anything version-dependent or about a library comes from its documentation or the code in the repository, not from memory. Every claim in the plan carries its source; a guess is written as an assumption.
- **Web searches** name libraries, versions and error messages only: never the client's or the product's name, domains, identifiers, data or code.
- **Ask the owner** only what research cannot answer. Give 2–4 options with your recommendation. Ask when you are blocked, not at the end.
- **State:** after every step below, rewrite the plan file's `State` section. It, and git, are the truth; what you remember is not.

## Plan file

`~/.claude/assist/<repo>/<slug>.md`, where `<repo>` is the repository directory's name and `<slug>` 2–5 lowercase words from the task. It holds the approved plan and ends with:

```
## State

phase: plan | measure | approved | implementation | review | done | stopped
repository: <absolute path>
base: <full sha>
branch: <name or ->
reviewed: <short sha or ->
round: <n>
open findings:
  - <id>: <problem> | response: <fixed | disagree: reason | ->
decisions:
  - <decision the owner made in the session, one line>
```

## 0. Resume

If `$ARGUMENTS` is a path to an existing plan file, read it. Check `State` against git: `repository` is the current directory, `branch` exists, and `base` and `reviewed` are commits on it. On a mismatch, tell the owner what differs and stop. Otherwise continue from `phase`.

## 1. Contract and baseline

1. Read the task: with `gh issue view` if it is a GitHub issue in this repository; otherwise use the description the owner gave (from another tracker, they paste it).
2. Read the contract: `CLAUDE.md` / `AGENTS.md` at the root and on the way down to the code the task touches, README, contributing guide, the CI workflows, the test and lint commands (package scripts, Makefile, pyproject and the like) of the package or packages the task touches, and the branch and commit conventions from `git log --oneline -20`.
3. Record the baseline: run those test and lint commands once on the current branch. Note for each: passing, failing (which tests), or cannot run on this machine (and why). If no tests exist, the baseline is `none`.

Tell the owner the baseline in one or two lines before the plan. A suite that cannot run here is a question now, not at implementation.

## 2. Research and plan

Research read-only: the code, the repository's docs, and the web within the rules above. Then write the plan, in the owner's language unless they ask otherwise:

```
# <task title>

Task: <issue link or the owner's description, verbatim>
Goal: <one or two sentences>

## Acceptance criteria
1. <observable behaviour, testable>

## How each criterion is proven
1. <test file and what it checks, or a manual check the owner runs>

## Assumptions
- <assumption> (source, or "my assumption")

## Files likely touched
## Out of scope
## Baseline
<from step 1>
```

- **No tests in the repository** (baseline `none`): ask one question. Add a test framework (a new dev dependency the client sees in the diff), or no automated tests and a manual check per criterion that the owner runs and the pull request description lists.
- **Measure first:** when the right values (thresholds, limits, choices) depend on data, say so in the plan and set `phase: measure`. Write the measurement script outside the repository (next to the plan file), run it, and bring the result to the owner. Fix the criteria only after the owner has seen it. Nothing from the measurement is committed unless the plan says so.

Show the plan to the owner. Change it until they approve it. Then write it to the plan file with `State` (`phase: approved`).

## 3. Branch

1. Stop unless `git status --porcelain` is empty: the owner commits or stashes their own work first.
2. If the current branch is the default branch (`git symbolic-ref --short refs/remotes/origin/HEAD`), `git fetch` and branch from `origin/<default>`. Otherwise branch from the current branch, and tell the owner.
3. Name the branch by the repository's convention; if it has none, `feat/<slug>` or `fix/<slug>`.
4. Record `base` (the full sha you branched from) and `branch` in `State`.
5. Tell the owner: the implementer edits files and runs commands. To avoid a prompt per edit, switch this session to accept-edits or auto mode now (Shift+Tab). Their deny rules still apply to subagents.

## 4. Implementation

Start `assist:implementer` with: the plan file's path, the base sha, the branch, the task `implement`, and the baseline. Set `phase: implementation`.

- `blocked`: record it in `State` (`phase: stopped`), tell the owner the reason, and stop. Continue only from the owner's decision, which goes into `decisions`.
- `implemented`: run the checks.

### Checks

- `git status --porcelain` is empty, and `git log --oneline <base>..HEAD` has the implementer's commits.
- Run the test and lint commands from the baseline yourself. Every criterion's test passes, and nothing fails that passed in the baseline.
- The implementer's return has a red run for each criterion with an automated test.

If a check fails, send it back to the implementer as a finding with the output (it counts as a round), or stop and tell the owner if it is the environment, not the code.

## 5. Review

Start `assist:reviewer` with: the plan file's path, the round, the baseline, your check results, and the diff `git diff <base>...HEAD -- . ':(exclude)*.lock' ':(exclude)*-lock.json' ':(exclude)*-lock.yaml'` (exclude the repository's other lock and generated files too). From round 2 on, also the previous findings, the implementer's responses, and the diff since `reviewed`. Set `phase: review`, and after it returns `reviewed` to `git rev-parse --short HEAD`, and the findings into `open findings`.

- `approve`: go to step 6.
- `changes`: if `round` is 2, stop and give the owner the open findings and the responses: they decide. Otherwise raise `round`, start the implementer with the task `fix` and the blocking findings, run the checks, and review again.

The reviewer may withdraw a finding after a `disagree`; a finding the owner closes in the session is a decision and is not raised again.

## 6. Ready for the owner

Set `phase: done` and give the owner:

1. Criterion → proof (test name, or the manual check to run).
2. The reviewer's "Where to look".
3. Non-blocking findings, one line each.
4. A proposed pull request description: goal, criteria and how they are proven, assumptions, and anything the owner checks by hand. Follow the repository's PR template if it has one.

Push and open the pull request only when the owner asks, with the tool the repository uses. Never merge.
