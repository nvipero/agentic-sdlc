# Step 3 plan: Implementation chain

Status: approved by owner, 2026-10-29 (draft 2, after Fable review)
Spec: `specs/factory-v1-spec.md` revision 7, section 10, step 3
Date: 2026-10-29

## TL;DR

- **What gets built:** three roles (test writer, implementer, code reviewer) and `/factory:run` extended from an approved spec to a pull request: acceptance tests first, then the implementation, then review, then a ready PR with a "Where to look" section.
- **Exit (spec section 10):** a story reaches a PR with passing local tests, a reviewer approval and a "Where to look" section. The run uses issue #28, which also creates the Todo-app's first code.
- **Main technical choice:** Playwright's browsers are installed in the image at build time, so the firewall stays closed. Microsoft's download CDN sits on shared addresses, like the documentation sites we did not open in step 2.
- **Where I need you:** approve this plan, merge the factory PR and the pilot PRs, run `/factory:run 28`, and review the resulting PR. You merge it or ask for changes.
- **Most likely reason this slips:** the first story also has to scaffold the whole app (Vite, React, TypeScript, Vitest, Playwright). That is more work than any later story, and the test environment in the container is new.

## Changes from draft 1 (Fable review, 2026-10-29)

No blocking findings. All ten non-blocking ones are taken:

| # | Change | Section |
|---|---|---|
| 1 | The Playwright version travels in the image as `PLAYWRIGHT_VERSION`; the test writer installs exactly it, and the orchestrator refuses a mismatch | 4 |
| 2 | The acceptance contract has concrete values and runs at the repository root (`cwd`) | 1 (decision 3), 4 |
| 3 | Any change to approved tests reopens the test gate; the approved commit moves only on approval; what `tests-change-approved` leads to | 1 (decision 9), 3 |
| 4 | The template ships a `.gitignore` the owner owns; the orchestrator checks for ignored files under `tests/acceptance/` before counting runs | 3, 4 |
| 5 | The implementation phase's state fields and resume table are designed before `run.md` is written | 3 |
| 6 | First story: selector rule for tests written before the UI exists; "failing before implementation" for #28 means the app does not start; both test commands named | 2, 3 |
| 7 | Two more spec changes listed (code reviewer writes nothing; disputes stay on the issue) | 7 |
| 8 | Exit check installs `@playwright/test` as `node` in a temporary directory to start Chromium, and checks that `node` cannot install browsers | 6 |
| 9 | Test writer and implementer do not send research requests: they read library documentation themselves (npm, `node_modules`, GitHub), and an unsettled question goes into "Where to look" | 2 |
| 10 | The pilot PR's contents are listed | 5 |

## 1. Decisions in this plan

Technical choices I made, with the reason. Each one can be overruled.

| # | Decision | Reason |
|---|---|---|
| 1 | **No story worktrees in v1.** Stories run one at a time on their branch in `/workspace` | The read-only overlays exist only in `/workspace`, and v1 is not optimised for parallelism (spec section 1). One checkout keeps the overlays in force. Spec change, section 9 |
| 2 | **Playwright browsers in the image.** The Dockerfile installs a pinned Playwright version's Chromium with its system packages at build time, under a root-owned path | The firewall stays closed. Opening Microsoft's CDN would open shared addresses. The cost: the project must pin the same `@playwright/test` version, and a version change rebuilds the image |
| 3 | **Acceptance tests are a separate package** in `tests/acceptance/` with its own `package.json`, and start the app through a fixed contract in `config.yaml`: `acceptance: {start: "npm run dev -- --strictPort", url: "http://localhost:5173"}`. `start` always runs at the repository root: the Playwright config sets `cwd: '../..'` and `reuseExistingServer: false` | The test writer works before any app code exists (principle 8), and owns only `tests/acceptance/`. The contract tells both roles how the app is started, without the test writer touching app files. Playwright runs the web server in the config file's directory by default (playwright.dev/docs/test-webserver), so the root must be explicit |
| 4 | **The implementer owns the project's root files** (`package.json`, lockfile, `tsconfig.json`, Vite and lint configuration, `index.html`) in addition to `src/` and `tests/unit/` | Someone must own them, and the spec's role table names no owner. They belong to the implementation. Spec change |
| 5 | **The orchestrator runs the tests** (`npm ci`, unit tests, acceptance tests) and records the results. Roles run tests too, but the orchestrator's run is the one that counts | The same rule as for commits: the orchestrator checks, it does not trust a report. Step 4 moves this to CI |
| 6 | **The orchestrator opens the draft PR**, not the implementer | The same model as step 2: roles commit, the orchestrator pushes and talks to GitHub. Spec change |
| 7 | **The code reviewer is read-only and has no web access** (Read, Grep, Glob, Skill). It gets the diff and the test results from the orchestrator | It produces findings and the "Where to look" section, no files, so "must not edit files" holds at the tool level. Everything it reviews against is in the repository. A library question it cannot settle goes into "Where to look" as an uncertainty, or becomes a research request. Without web access, no web page can steer the section the owner reads instead of the code |
| 8 | **Two review gates:** the code reviewer checks test coverage after the test writer (spec section 5, "Tests"), and the implementation after the implementer | The spec's workflow has both. The same review loop rules apply to each |
| 9 | **A wrong acceptance test goes back through the orchestrator.** The implementer may not change `tests/acceptance/`. If it believes a test is wrong, it returns `test_problem`; the orchestrator sends it to the test writer once, and after that to the owner. **Any change to approved tests reopens the test gate:** the code reviewer reviews coverage again, and the approved-tests commit moves only on its approval. If the owner adds `tests-change-approved`, the test writer applies the owner's decision; the implementer still never touches the path, and the label stays as the record for step 4's guard | Principle 8 and the acceptance test guard (spec section 8). Without the reopened gate, an implementer's claim could weaken a test with only a path check in between |
| 10 | **The PR closes the issue** (`Closes #<n>` in its description) and is marked ready for review when the code reviewer approves and the orchestrator's test run passes | The owner merges; the issue follows. Gates and the preview come in step 4 |
| 11 | **The light path** (`trivial` label: no spec review, no acceptance tests) is not built in step 3 | Nothing needs it yet. It is a small addition once the full path works |

## 2. Roles

| Role | Tools | Writes | Commits (trailer) |
|---|---|---|---|
| Test writer | Read, Grep, Glob, Write, Edit, Bash, Skill | `tests/acceptance/` | `test(acceptance): …`, `Factory-Role: test-writer` |
| Implementer | Read, Grep, Glob, Write, Edit, Bash, Skill | `src/`, `tests/unit/`, the root project files (decision 4) | `feat(…)`/`fix(…)`, `Factory-Role: implementer` |
| Code reviewer | Read, Grep, Glob, Skill | nothing | none |

- **Test writer:** one or more Playwright tests per acceptance criterion, named with the criterion's id (`AC-3: …`), against the contract in `config.yaml`. It installs `@playwright/test@"$PLAYWRIGHT_VERSION"` with `--save-exact`. Before any implementation, the tests must fail because the behaviour is missing, not because the test is broken: the test writer says which. For the first story the app does not exist yet, so "failing" means the web server cannot start.
- **Selectors:** tests are written before the UI exists, so they find elements by role and accessible name (`getByRole`, `getByLabel`) with names taken from the spec's words, never by CSS or test ids. The coverage review checks this, and the implementer builds the UI to match.
- **Implementer:** the smallest code that makes the acceptance tests pass, with unit tests for its own logic. It follows the spec's assumptions and does not widen the scope. For the first story it also sets up the project (Vite, React, TypeScript, Vitest), with versions checked at implementation time.
- **Code reviewer:** against the spec, the conventions, architecture boundaries and a short security checklist (input handling, storage, dependencies added). It writes the "Where to look" section: restricted-list hits (spec section 7), deviations from the spec, assumptions the implementation made, and places where it is uncertain.
- **No research requests from these two roles.** They have Bash, and library documentation is reachable through `npm view`, `node_modules/*/README.md` and GitHub. A library question they cannot settle goes into "Where to look" as an uncertainty.
- **Commit rule, languages and source rules** are the same as in step 2.

## 3. `/factory:run`, implementation phase

The run continues from `spec-approved`. Each run still reads GitHub and git first and keeps one status comment.

1. **Tests:** the test writer writes the acceptance tests and commits. The orchestrator checks the commit paths and runs the tests: they must fail. The code reviewer checks coverage (every criterion has a test, each test checks what its criterion says, selectors follow the rule). Review loop rules apply. On approval the orchestrator records the approved-tests commit.
2. **Implementation:** the implementer writes the code and commits. The orchestrator checks the paths, including `git diff --stat <approved tests> HEAD -- tests/acceptance` being empty and `.gitignore` unchanged, and that `git clean -ndx -- tests/acceptance` lists nothing but `node_modules/`, `test-results/` and `playwright-report/`. Then it runs both test commands: `npm ci` and the unit tests at the root, and `npm ci` and Playwright in `tests/acceptance/` (`npm ci` replaces any existing `node_modules`).
3. **Draft PR:** after the first implementation commit, the orchestrator pushes and opens a draft PR with `Closes #<n>`.
4. **Review:** the code reviewer gets the diff, the spec and the test results. Its findings go back to the implementer. Review loop rules apply.
5. **Ready:** when the reviewer approves and the orchestrator's test run passes, the orchestrator writes the PR description (TL;DR, what changed, test results, "Where to look"), marks the PR ready for review, and posts the `ready` comment on the issue with the PR link.

**State and resume:** before `run.md` is written, the status comment's state line gets the implementation phase's fields: phase (`tests` or `implementation`), the approved-tests commit, the PR number, the number of `test_problem` returns, and separate round and rework counters for the two gates. A table like `run.md` section 4 decides a resumed run: tests committed but not reviewed, tests approved but nothing implemented, PR open with a review pending.

**Comments:** the same rules as step 2. The PR description carries the TL;DR and "Where to look"; the issue gets only the status comment and the owner-facing comments.

## 4. Test environment in the container

- **Image:** Node 24 stays. The Dockerfile sets `ARG PLAYWRIGHT_VERSION` and `ENV PLAYWRIGHT_VERSION=… PLAYWRIGHT_BROWSERS_PATH=/ms-playwright` (as image environment, so plain shells and the exit check see them), and installs Chromium with its system packages at build (`npx playwright@$PLAYWRIGHT_VERSION install --with-deps chromium`, as root). It then clears root's npm cache. Firefox and WebKit are left out until a story needs them. Debian 13 is supported from Playwright 1.55 (playwright.dev/docs/intro).
- **Browsers path not writable by `node`:** tested on 2026-10-29 with Playwright 1.64.1: Chromium starts headless as `node` from the root-owned `/ms-playwright` (a one-line test passed in 604 ms). No change to the official image's mode is needed.
- **Project:** `tests/acceptance/package.json` pins `@playwright/test` to `$PLAYWRIGHT_VERSION` exactly. The orchestrator refuses to run the tests when the two differ, with that message.
- **`.gitignore`:** the template ships one (owner-owned, like the other factory files outside the overlays), covering `node_modules/`, `test-results/`, `playwright-report/` and the build output.
- **npm:** `registry.npmjs.org` is already allowlisted. Packages' install scripts run inside the sandbox, which is what the sandbox is for.
- **App under test:** started on loopback inside the container by the contract command, which the firewall allows. You do not see the running app before step 4's preview.
- **To verify while building:** that the browser download at image build works through Docker's build network, the exact Playwright version, and that Chromium starts headless as `node`.

## 5. Exit: the Todo-app run

1. The factory PR and one pilot PR are merged, the host clone pulled, the image rebuilt by `up.sh`, and a new Claude session started. The pilot PR carries the Dockerfile change, `.gitignore`, the `acceptance` block hand-merged into the pilot's `config.yaml`, the new `.factory/` content, and `CLAUDE.md`'s ownership table with the root files under the implementer.
2. You run `/factory:run 28`. The run writes the tests, scaffolds the app, implements #28, reviews, and opens the PR.
3. You review the PR through its description and "Where to look", and merge it or ask for changes. Merging is your step; step 3's exit is the ready PR.
4. Optional, if time allows: #29 or #31 on top of #28, to see a story on an existing codebase.

## 6. Exit check and evidence

**Scripted (added to `scripts/exit-check.sh`):**
- As `node`, in a temporary directory: `npm i @playwright/test@"$PLAYWRIGHT_VERSION"` and a one-line test that starts Chromium headless. `node` cannot write to `/ms-playwright`. (Tested while building: `npx playwright install` as `node` does not fail, it hangs without changing anything, so the check is the write, and the test writer's skill forbids running `playwright install`.)
- `PLAYWRIGHT_VERSION` in the image equals the pin in `tests/acceptance/package.json` on `main`, once that file exists.
- The three new role definitions have the tools in section 2; the code reviewer has no write tool and no web tool.
- The step 1 and 2 checks still pass.

**From the real run (`docs/verification/step-3.md`):**
- The PR: description with TL;DR and "Where to look", `Closes #28`, ready for review.
- Commits in order (spec, tests, implementation), each touching only its role's paths with a parsed `Factory-Role` trailer; `tests/acceptance/` unchanged after the test review.
- The orchestrator's test runs: tests failing before the implementation and passing after.
- The review rounds, and the status comment's open findings surviving a resumed run if one happens (left untested in step 2).

## 7. Spec changes (revision 8)

- Section 4: no story worktrees in v1 (decision 1); the layered sandbox becomes the first step of v2, merged with backlog item 11 (owner decision, 2026-10-29).
- Section 4: `tests/acceptance/` is its own package, and `config.yaml` gets the `acceptance` contract (decision 3).
- Section 6: the implementer owns the root project files (decision 4); the orchestrator opens the PR and writes its description (decision 6); the code reviewer reviews tests and implementation (decision 8) and writes nothing itself: its findings and "Where to look" go through the orchestrator (decision 7).
- Section 5, "Spec to merge" item 4: a dispute is raised on the issue, not the PR, following step 2's comment rules.
- Section 5, "Spec to merge": the orchestrator runs the tests (decision 5) and the wrong-test path (decision 9).

## 8. Known limitations in step 3

- **Agents now open pull requests,** and the token can still merge them until step 4. The deny rule and the commit checks are the only barriers, as recorded since step 1.
- **You get no GitHub notifications from the factory.** GitHub does not notify you about your own actions, and the agents act as you until step 4. The session and the issue are where you see progress.
- **Path rules are the orchestrator's checks, not CI,** until step 4's gates.
- **The image now carries a browser.** It is larger, and a Playwright upgrade means an image rebuild.

## 9. Where I need you, and what can go wrong

- **You:** approve this plan; merge the factory PR and the pilot PRs; run the story; review and merge the PR.
- **I do on my own:** everything else, and I report results and deviations.
- **Most likely reasons this slips:**
  - The first story's scaffolding is large, and the implementer's choices (versions, structure) set the pattern for every later story. The code reviewer checks them against the spec's stack (spec section 9).
  - Playwright in the container: the browser download at build time, or Chromium's system packages on Debian trixie.
  - The status comment grows long on a story with many rounds. Its format was untested with many entries.
