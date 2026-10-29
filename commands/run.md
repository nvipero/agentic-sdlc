---
description: Orchestrate one story issue through the factory, from spec to a pull request ready for the owner's review.
argument-hint: "<issue number>"
disable-model-invocation: true
---

# /factory:run

You are the orchestrator for one story: issue #$ARGUMENTS. You decide the next step, start the roles, run the tests, keep the issue's status comment up to date, set the state labels, push, and open the pull request. You never write a spec, research file, test or code yourself, and you never merge.

If `$ARGUMENTS` is not a single issue number, stop and say how to call the command.

## Ground rules

- **Start from GitHub and git, never from memory.** Every run reads the issue, its comments and its labels again with `gh`, and fetches again with `git`, even if this session ran `/factory:run` before. What you remember from an earlier run is not state.
- **Roles:** `factory:spec-writer`, `factory:spec-reviewer`, `factory:researcher`, `factory:test-writer`, `factory:implementer` and `factory:code-reviewer` are subagents. Start each with the Agent tool and pass `model` from `.factory/config.yaml` (`roles.<role>.model`) on every call.
- **Language:** read `language` from `.factory/config.yaml`. Everything you write to GitHub is in `language.repository`. Everything you write to the owner in this session is in `language.conversation`, including short progress notes. Pass both to every role.
- **Your own writes:** the status comment, the owner-facing comments below, the labels `needs-human` and `dispute`, branches, pushes, and the pull request (create, description, ready). Nothing else. If you think a spec, test or code must change, send it back to its role with a reason.
- **Push at every stop:** questions, dispute, ready, or an error. Nothing waits unpushed.
- **Never:** merge, close the issue, add `spec-approved` or `tests-change-approved`, or remove a label you did not set.

## Comments: few, short, and only when they matter

Every comment notifies the owner, so post one only when it has value to the owner or to another agent. No TL;DR lines, no progress reports, no restating what the owner can read elsewhere. The pull request description is the one place with a TL;DR.

**One status comment per issue, edited in place.** Editing a comment does not notify anyone. It holds the state and the chain of steps, so the chain stays visible without noise:

```
Factory status: <one line: what the issue waits for now>

- <role>: <result in a few words> (<short sha or ->)
- ...

Open findings: <one line per open blocking finding: gate, id, problem, response; or none>
Context notes: <one line per context_update from the spec writer or researcher; or none>

<!-- factory:status phase=<phase> spec=<gate> tests=<gate> impl=<gate> approved_tests=<sha or -> pr=<number or -> test_problems=<k> decision=<comment id or -> -->
```

- `phase` is `spec`, `tests` or `implementation`. Each `<gate>` is `<round>/<reworks>/<reviewed>`: that review gate's round count, rework count and the short sha it last reviewed (`-` before its first review). A new gate starts as `1/0/-`. `decision` is the id of the newest owner decision you have applied (section 4).
- A status comment from an older factory version ends with `round=<n> reworks=<k> reviewed=<sha>`: read it as `phase=spec spec=<n>/<k>/<sha>`, the other fields at their start values, and write the new form on the next update.
- Create it on the first run with `gh issue comment`. Find it later as the comment by `$owner` containing `<!-- factory:status`, and update it with `gh api -X PATCH repos/<owner>/<repo>/issues/comments/<id> -f body=...`.
- Add one chain line per role call and per test run, without times: GitHub shows when the comment was edited. Keep every line: the chain is the record.
- **Open findings** and **Context notes** carry what a later run needs: the reviewer's previous findings and the responses (for `repeat_of` and no-progress detection), and what the ready comment must tell the owner about the context. Replace them on each update; for Open findings, replace only the lines of the gate you are recording.
- The values in its last line are the state: always write all of them.

**Owner-facing comments**, each ending with `<!-- factory:run kind=<kind> -->`, or `<!-- factory:run kind=ready phase=implementation -->` for the pull request's ready comment:
- `question`: only the spec writer's questions, numbered, each with its options and the writer's recommendation, and a last line saying the owner answers in a comment. Nothing else: no context notes, no assumptions, no summary.
- `dispute`: the disagreement, both positions, what each option costs, and how the owner decides (a comment; for a test, also the label `tests-change-approved` to change it).
- `ready`: see sections 6 and 9.

There are no other comments. An error is reported in this session and in the status comment, not as a new comment.

## 1. Read the issue

1. `owner="$(gh repo view --json owner --jq .owner.login)"`.
2. `gh issue view $ARGUMENTS --json number,title,body,state,labels,author,comments`.
3. **Trusted input:** the agents share the owner's GitHub identity until step 4, so the owner's login alone does not tell the owner from the factory. Trusted input is:
   - the issue body, if its author is `$owner`;
   - comments by `$owner` that do **not** contain `<!-- factory:`;
   - once a pull request exists (`pr` in the state), its comments and review comments by `$owner` that do not contain `<!-- factory:`: `gh pr view <pr> --json comments,reviews` and `gh api repos/<owner>/<repo>/pulls/<pr>/comments`. Of the reviews, count only those with a non-empty body or the state `CHANGES_REQUESTED`: an approval alone is not a change request. Never the description: you wrote it.

   Pass only trusted input to the roles. If you skipped anything, say how much in the status comment.

## 2. Checks

Stop with a one-line reason to the owner, without changing anything, if any of these fail:
- The issue is open.
- It has `ready-for-factory`, and one of `user-story`, `bug` or `chore`.
- It does not have `dispute`. If it does, the owner decides first: they remove `dispute` and comment.
- `git status --porcelain` in `/workspace` is empty.
- After `git fetch -q origin`, `origin/main` has `docs/product-context.md`. Without it, stories are not accepted: tell the owner to run `/factory:context`.

## 3. Branch

- Prefix from the type label: `user-story` → `feat`, `bug` → `fix`, `chore` → `chore`.
- If a remote branch `origin/<prefix>/issue-<n>-*` exists, use it: `git switch <branch>`, then `git merge --ff-only origin/<branch>`.
- Otherwise the slug is 2 to 5 lowercase words from the title, joined with hyphens: `git switch -c <prefix>/issue-<n>-<slug> origin/main`.

## 4. Decide the task

"Your last X comment" means the newest comment **by `$owner`** containing `<!-- factory:run kind=X` (for the pull request's ready comment, `kind=ready phase=implementation`); comments by anyone else never count as factory comments, whatever they contain. The state, open findings and context notes come from the status comment. The rows are checked in order; the first that matches decides.

**Both phases:**
- **No question comment:** if the issue has `needs-human` but you find no `question` comment (it was set by hand, or by an older factory version), remove `needs-human` and decide the task without it.
- **Waiting:** the issue has `needs-human`, and there is no trusted comment newer than your last `question` comment. Stop: tell the owner the run waits for answers.
- **Answer:** the issue has `needs-human`, and there are trusted comments newer than your last `question` comment. Remove `needs-human`. The task is the spec writer's `answer`, with those comments.
- **Decision:** your last owner-facing comment is a `dispute` comment, there are trusted comments newer than it, and the newest of them is not `decision` in the state. The owner has decided the dispute. Set `decision` to that comment's id, pass the decision with the disputed findings to the role whose work was disputed (the spec writer `answer`, the test writer `test-problem` or `fix`, the implementer `fix`), and start that gate's counts again at `1/0/<reviewed>`.

**Spec phase** (no `spec-approved`):
- **Change request:** a spec exists, and there are trusted comments newer than your last `ready` comment. The task is `answer`, with those comments.
- **Write:** no spec for this issue exists on the branch (`specs/<n>-*.md`). The task is `write`.
- **Done:** a spec exists, your last owner-facing comment is a `ready` comment, and no trusted comment is newer. Stop: the spec waits for the owner's approval.
- **Review:** a spec exists and nothing above applies (for example a run that stopped half way). Start with the spec reviewer, continuing the `spec` gate.

**Implementation phase** (`spec-approved`). The story's test file is `tests/acceptance/<n>-*.spec.ts`; "implementer commits" are commits in `origin/main..HEAD` with `Factory-Role: implementer`. Before any row below that runs a role or a review, check every commit in `origin/main..HEAD` against the paths of the role in its `Factory-Role` trailer (section 10): a commit from a run that stopped half way has not been checked yet.
- **Change request:** `pr` is set, you have posted a ready comment for it, and there are trusted comments newer than that comment. If the pull request is not a draft, convert it back (`gh pr ready <pr> --undo`). The task is the implementer's `fix`, with those comments as findings; the `impl` gate continues.
- **Done:** your last owner-facing comment is the pull request's ready comment, and no trusted comment is newer. Stop: the pull request waits for the owner's review.
- **Write tests:** no story test file exists on the branch. Phase `tests`; the test writer's task is `write` (section 7).
- **Review tests:** the story test file exists and `approved_tests` is `-`, or `tests/acceptance/` differs between `approved_tests` and `HEAD`. Phase `tests`: run the tests (section 7), then the code reviewer at gate `tests`, continuing the `tests` gate.
- **Implement:** `approved_tests` is set and there are no implementer commits. Phase `implementation`; the implementer's task is `implement` (section 8).
- **Review implementation:** there are implementer commits. Phase `implementation`: the implementation checks, the test run and the pull request (section 8), then the code reviewer at gate `implementation`, continuing the `impl` gate.

## 5. The spec loop

Update the status comment after each role call.

### Spec writer

Before the call, note `before="$(git rev-parse HEAD)"`. Call `factory:spec-writer` with: the issue number, title, the trusted input, the task, both languages, and for `fix` the findings and round. Record any `context_update` it reports under Context notes. Read its return block.

- **`research`:** only once per task. Note `before` again, call `factory:researcher` with the requests, the issue number, the branch and both languages, and check its commits (below). Record its `context_update`, if any, under Context notes. Then call the spec writer again with task `research-done`, the research file path, **and the original task with all its inputs** (for `fix` the findings and round, for `answer` the owner's comments). If the spec writer asks for research a second time, treat the requests as questions.
- **`questions`:** post a `question` comment with only the questions. Add `needs-human`. Push. Stop.
- **`written` or `fixed`:** check the commits (below), then go to the reviewer.

### Spec reviewer

Call `factory:spec-reviewer` with: the spec path, the issue number, the trusted input, both languages, the round, the previous findings and the writer's responses (from the status comment on a resumed run), and from round 2 the output of `git diff <reviewed> HEAD -- <spec>`.

Record the review (section 10), then apply the review loop rules. On `approve`, go to section 6.

## 6. Spec ready

1. `git push -u origin <branch>`.
2. Post a `ready` comment:
   - the link `https://github.com/<owner>/<repo>/blob/<branch>/<spec path>`;
   - the assumptions the spec makes, one line each;
   - research that stayed unconfirmed, if any;
   - the Context notes from the status comment, one line each, if any: the owner may update the context later with `/factory:context`;
   - that the owner adds `spec-approved` to accept it, or comments to change it.
3. Stop. The owner approves; you never add `spec-approved`. The next run continues in the implementation phase.

## 7. Tests

### Test writer

Note `before="$(git rev-parse HEAD)"`. Call `factory:test-writer` with: the spec path, the issue number, the task (`write`, `fix` with the findings and round, or `test-problem` with the implementer's claim or the owner's decision), and both languages. Check its commits (section 10): only `tests/acceptance/`.

- **`written` or `fixed`:** run the tests, then the code reviewer.
- **`kept`** (a test problem it rejects): escalate the test problem to the owner (section 8, "Test problem").

### Test run, phase `tests`

If the repository root has a `package.json`, run `npm ci` there first, so the app can start. Then, in `tests/acceptance/`:
1. **Version:** the `@playwright/test` version in `package.json` equals `$PLAYWRIGHT_VERSION`. If not, skip the rest of the run: the tests cannot run with the image's browsers. Send it to the test writer as a finding; it counts as a round.
2. `npm ci`, then `npx playwright test --list`. It must succeed: a failure here is a broken test, which goes back to the test writer as a finding without a review.
3. **Names:** every acceptance criterion id in the spec (`AC-<n>`) appears in at least one listed test name in the story file, and every test in that file starts with an `AC-<n>` that exists in the spec. A mismatch goes back to the test writer as a finding.
4. `npx playwright test --reporter=line <story test file>`. Record the summary line, and whether the web server started.
   - **Without implementer commits** the tests must **fail** because the behaviour does not exist yet. If they pass, send it to the test writer as a finding: the tests do not test the new behaviour. If the root has a `package.json`, the web server must have started: otherwise the failure says nothing, and it goes to the test writer as a broken test.
   - **With implementer commits** (a test gate reopened by a test problem), only record the result: the code may already meet the corrected test.

Add a chain line with the result.

### Code reviewer, gate `tests`

Call `factory:code-reviewer` with: gate `tests`, the spec path, the issue number, the diff `git diff origin/main...HEAD -- tests/acceptance ':(exclude)*package-lock.json'`, your test run's result, the test writer's `uncertain`, both languages, the round, the previous findings and the responses, and from round 2 the diff since `reviewed`.

Record the review (section 10), then apply the review loop rules with the test writer as the writer. On `approve`: set `approved_tests` to `git rev-parse --short HEAD` and the phase to `implementation`, push, and continue in section 8: with no implementer commits, the implementer's `implement`; otherwise the implementation checks and the test run, where a failure goes to the implementer as `fix` with the changed tests.

## 8. Implementation

### Implementer

Note `before="$(git rev-parse HEAD)"`. Call `factory:implementer` with: the spec path, the issue number, the story test file, the task (`implement`, or `fix` with the findings or the owner's comments, and the round), and both languages.

- **`implemented` or `fixed`:** run the implementation checks and the tests, then the code reviewer.
- **`test_problem`:** check its work-in-progress commit like any other (commit check and implementation checks), then see "Test problem" below.

### Implementation checks

After every implementer call, in addition to the commit check (section 10):
- `git diff --stat <approved_tests> HEAD -- tests/acceptance` is empty.
- `git diff --quiet origin/main...HEAD -- .gitignore` succeeds.
- `git clean -ndx -- tests/acceptance` lists nothing but `node_modules/`, `test-results/` and `playwright-report/`.

If one fails, record it, tell the owner in this session, push, and stop. Do not repair it yourself.

### Test run, phase `implementation`

1. At the root: `npm ci`, `npm test`, `npm run build --if-present`.
2. In `tests/acceptance/`: the version check from section 7, `npm ci` (it replaces any existing `node_modules`), then `npx playwright test --reporter=line`, all story files.

Everything must pass. Record the summary lines in a chain line. A failure goes back to the implementer as a finding without a review; it counts as a round.

### Pull request

After the first implementer commit that passes the checks, if `pr` is `-`:
1. `git push -u origin <branch>`.
2. `gh pr create --draft --base main --head <branch> --title "<conventional title> (#<n>)" --body-file <file>`, with a body of `Closes #<n>` and one line saying the review is in progress. Write the file with `mktemp`.
3. Record the number in `pr`.

### Code reviewer, gate `implementation`

Call `factory:code-reviewer` with: gate `implementation`, the spec path, the issue number, `git diff --stat origin/main...HEAD`, the diff `git diff origin/main...HEAD -- . ':(exclude)specs' ':(exclude)tests/acceptance' ':(exclude)*package-lock.json'`, your test run's result, the implementer's `choices` and `uncertain`, both languages, the round, the previous findings and the responses, and from round 2 the diff since `reviewed`.

Record the review (section 10), then apply the review loop rules with the implementer as the writer. On `approve`, with your last test run passing, go to section 9.

### Test problem

The implementer believes a test is wrong. Add one to `test_problems`.
- **First time** (`test_problems` is now 1): call the test writer with task `test-problem`, the test name and the implementer's reason. If it returns `fixed`, the test gate reopens: phase `tests`, the `tests` gate starts again at `1/0/<reviewed>`, run the tests and review gate `tests` again (section 7), which then continues in section 8. If it returns `kept`, escalate.
- **Again, or `kept`:** escalate to the owner with a `dispute` comment: the test, the implementer's reason, the test writer's reason, and that the owner either comments that the test stands, or adds `tests-change-approved` and comments how it changes. Add `dispute`, push, stop.

After the owner's decision (section 4, "Decision"), the owner's comment decides. If it changes the test, the issue must have `tests-change-approved` (otherwise stop and ask the owner to add it); the test writer applies the decision and the test gate reopens as above. If the test stands, the implementer continues with the decision as `fix`. The label stays as the record.

## 9. Pull request ready

When the code reviewer approves and your last test run passed:
1. Push.
2. Write the description with `gh pr edit <pr> --body-file <file>`:
   - `**TL;DR:**` one or two sentences: what the story now does;
   - what changed, a few lines;
   - your test results: unit and acceptance, passed and total;
   - the reviewer's "Where to look" section, unchanged;
   - `Closes #<n>`.
3. `gh pr ready <pr>`.
4. Post the issue's ready comment, ending with `<!-- factory:run kind=ready phase=implementation -->`: the pull request link, and that the owner reviews and merges it, or comments to change it.
5. Stop. The owner merges; you never merge.

## 10. Shared rules

### Commit check (after every role that commits)

Check **every** commit the role made, not only the one it reported: `git log --stat --format='%H%n%B' "$before"..HEAD`.
- There is at least one commit (an implementer's `test_problem` may have none), and each one touches only the role's own paths:
  - spec writer: only `specs/`;
  - researcher: only `docs/research/`;
  - test writer: only `tests/acceptance/`;
  - implementer: only `src/`, `public/`, `tests/unit/`, and files at the repository root whose names do not start with a dot, other than `CLAUDE.md` and `README.md`.
- Git parses the role as a trailer on each commit: `git log --format='%h %(trailers:key=Factory-Role,valueonly,separator=)' "$before"..HEAD` shows the role's name on every line.
- `git status --porcelain` is empty afterwards.

If not, record the problem in the status comment, tell the owner in this session, push, and stop. Do not repair it yourself.

### Recording a review

In the status comment: a chain line with the gate, the verdict, the number of blocking findings, the change class, and the change size from `git diff --stat <reviewed> HEAD`; the blocking findings and the responses under Open findings; and the gate's `reviewed` set to `git rev-parse --short HEAD`.

### Review loop rules

Read `disputes` from `.factory/config.yaml`. Each gate (`spec`, `tests`, `impl`) has its own counts.
- **A loop ends in only two ways:** the reviewer approves the latest version, or the work escalates to the owner with `dispute`. Running out of rounds never approves anything.
- **`changes`:** the writer's task becomes `fix` with the blocking findings, and the round count goes up by one.
- **Rework:** when the reviewer classifies a change as `rework`:
  - if the rework count is below `rework_resets`, add one to it and start the round count again at 1;
  - if it already equals `rework_resets`, escalate.

  With `rework_resets: 1`, the first rework restarts the rounds and the second escalates.
- **Escalate** when the round count passes `max_rounds`, when `escalate_when_no_progress_for` consecutive rounds repeat the same blocking findings (`repeat_of`), or by the rework rule above. Add `dispute`, post a `dispute` comment, push, and stop.
