# Step 5 plan: First full run

Status: approved by the owner on 2026-10-31 (draft 2; draft 1 reviewed by a second model, findings in section 7)
Spec: `specs/factory-v1-spec.md` revision 10, section 10, step 5, and section 11
Date: 2026-10-31

## TL;DR

> **TL;DR:** Nothing new is built. You write one new story, the factory takes it from spec to a ready PR under the final step 4 setup, you merge it, and I check every definition-of-done item against GitHub's own records. Problems found on the way are written down, not fixed by hand in the pilot. If all items pass, v1 is done.

- **Exit (spec section 10):** definition of done (section 11) met and problems recorded.
- **Why a run is still needed:** no story has yet gone from idea to merge under the final setup. Step 4's real story (#31) had its spec approved before step 4, so the spec chain (researcher, spec writer, spec reviewer, question flow) has not run under the App identity, the trusted-input checks or the owner-label checks.
- **Where I need you:** write the story; answer the agents' questions; add `spec-approved`; review, approve and merge the PR; run two commands in the container for the network check.
- **Most likely reason this slips:** a factory defect in a path that has not run under the App yet (spec chain, question flow). The fix then goes through a factory PR and a pilot PR, and the run resumes, which costs a merge round each time.

## 1. Basis

No new technology; nothing to research. Inputs:
- Spec section 11 (definition of done) and principle 13.
- Step 3 and 4 verification: paths not exercised yet are a test problem from the implementer, a dispute and its decision, a resumed run with open findings, and a feature-removal story (planned in step 4, not run).
- State on 2026-10-31: pilot `origin/main` `.factory/` matches the factory's `main`. Your host clone of the pilot is two commits behind (`f144d19`), so `up.sh` refuses to start until you pull.

## 2. Decisions

| # | Decision | Reason |
|---|---|---|
| 1 | **Only the review's fixes before the run.** Step 5 builds nothing new. Three defects found in the second-model review of this plan are fixed first, in the same factory PR (section 7), and copied to the pilot before the story is written | The step tests v1 as it is. Changes found necessary during the run are recorded and go through the normal factory PR route |
| 2 | **No manual edits in the pilot during the run,** by you or me. A defect that blocks the run is fixed in the factory, copied to the pilot through a PR you merge, and the run resumes with `/factory:run` | A hand edit fails the first DoD item. A resume is itself an unexercised path |
| 3 | **Problems are logged as they happen** in `docs/verification/step-5.md`, with evidence links, and classified: blocking (stopped the run), defect, friction, idea | "Problems recorded" is part of the exit; recording only at the end loses detail |
| 4 | **The DoD is checked from GitHub's records, not from the agents' own reports:** issue events, comment authors and edit history, PR commits and authors, check runs on the merged head, the ruleset, and who merged. The `gh` commands go into the verification document so the check can be repeated | Principle 15. The agents' status comment is written by the agents |
| 5 | **No new DoD check script.** The commands are kept in the verification document | A reusable check belongs with the retro agent and evals (backlog 7); a one-off script is overengineering at the end of v1 |
| 6 | **Network item by observation:** the owner reads the firewall counters as root through `docker exec`: `iptables -L OUTPUT -v -n` (the REJECT rule), `ip6tables -L OUTPUT -v -n` (IPv6 has no REJECT rule; drops show in the policy line) and the container's start time (`docker inspect --format '{{.State.StartedAt}}'`). The counters reset on every container start, so they are read after start and before every stop, and summed. The step 1 exit check runs again after the run | The firewall does not log; counters are a cheap after-the-fact check. A non-zero count is not a failure by itself (the rule worked) but is investigated and recorded |
| 7 | **After a pass, v1 is closed:** spec revision 11 marks v1 done, the README status changes, and the problems list becomes a prioritised input for v2 (backlog item 11 first, by the owner's earlier decision) | Ends the build steps cleanly |

## 3. The run

| # | Who | What |
|---|---|---|
| 1 | You | `git pull --ff-only` in the pilot host clone; `scripts/up.sh`; read the network counters (decision 6) |
| 2 | You | Write the story as a new issue from the template |
| 3 | Agents | `/factory:run <n>`: spec writer with the understanding check, researcher if needed; questions to you in the issue |
| 4 | You | Answer the questions in full sentences, not only an option letter |
| 5 | Agents | `/factory:run <n>`: the spec writer applies the answers, spec reviewer; ready comment |
| 6 | You | Read the spec; add `spec-approved` |
| 7 | Agents | `/factory:run <n>`: test writer, coverage review, implementer, code review, GitHub checks, PR marked ready; preview deploys |
| 8 | You | Review the PR and the preview. A change request goes through a review, not a comment. Approve and merge |
| 9 | You | Read the network counters; then I run the exit check while the container is still up (it needs a running container and restarts it); then `scripts/up.sh stop` |
| 10 | Me | DoD check (section 4); `docs/verification/step-5.md`; problems list |

Steps 3 to 7 may take more runs (a review loop, a dispute, a research request); each is one more `/factory:run <n>`. Every stop in the session that leaves no trace on GitHub (the orchestrator asking or telling you something only in the session) is written to the verification document with the `run.md` rule that caused it.

## 4. Definition of done, and how each item is checked

| DoD item (spec section 11) | Evidence |
|---|---|
| A story written by the human reaches a merged PR without the human editing code | Issue author is you; PR merged; every commit on the PR has only the App (author name `factory <role>` or the App itself) and the `claude` co-author as authors, none by you |
| The human was asked only at defined points. Each pull request description and long document started with a TL;DR, and each question to the human carried only the question | Every App comment on the issue and PR, classified by type (status, question, dispute, ready); each question comment carries only the question; the PR description, the spec and any research file start with `> **TL;DR:**`; the session stops logged under section 3 |
| The spec's problem and why section is traceable to the approved project context | The spec's references resolve to sections of `docs/product-context.md` on `main`, or to the issue (`(issue: #n)`, allowed by spec section 5) with a `context_update` recorded in the status comment |
| All gates ran and were required for merge | Check runs on the merged head commit (they survive the branch deletion); the rule suite of the merge push (`gh api repos/<owner>/<repo>/rulesets/rule-suites?ref=refs/heads/main`, then `/rule-suites/<id>`), which lists the required checks, pull request and code scanning rules evaluated at merge time |
| No agent modified acceptance tests, factory definitions or gates | `guards` passed on the merged head; the PR's paths; acceptance-test changes after approval only with `tests-change-approved` added by you (issue events) |
| No agent merged a pull request | `merged_by` is you; no other PR merged by the App in the period |
| No agent accessed anything outside its container workspace or allowlisted network | Section 2, decision 6; exit check sections on mounts and network |
| Observed problems are written down for the next iteration | `docs/verification/step-5.md`, problems section |

## 5. Known limitations

- One run is one sample. It does not show that the factory works for every story, only that the chain closes once under the final setup.
- The researcher reaches only allowlisted hosts (Anthropic, GitHub, npm), so standards bodies and MDN stay out of reach and such sources are marked unconfirmed. Expected friction, recorded if it happens; the layered sandbox in v2 addresses it.
- The DoD check uses GitHub's records, which cannot show what an agent tried and was refused inside the container, except through the firewall counter and Claude Code's deny rules.

## 6. Where I need you

- **You:** approve this plan; then the steps in section 3.
- **I do on my own:** watch the run, log problems, fix blocking factory defects through factory PRs, the DoD check, the verification document and the v1 closing changes.

**Owner decisions, 2026-10-31:**
1. **Story type:** a new feature story. The feature-removal story stays untested in v1 and is carried to the problems list as an unexercised path.
2. **TL;DR rule:** the DoD follows principle 13. Spec revision 10, made with this plan, changes the DoD item to "each pull request description and long document started with a TL;DR, and each question to the human carried only the question".

## 7. Second-model review of draft 1

No blocking findings. Twelve non-blocking, all taken in; one suggested fix did not work and was replaced.
- **Fixed in the factory before the run (owner decision, 2026-10-31):**
  - The spec writer's `answer` task got only the owner's comments, not the questions they answer. The spec writer is a new session and cannot read GitHub, so an answer such as "1: B" meant nothing to it. The orchestrator now passes the questions from its last `question` comment (`commands/run.md`, `skills/spec-writer/SKILL.md`).
  - The `answer` instructions assumed a spec already existed; in a new story the questions come first. The spec writer now writes the spec with the answers applied.
  - The owner-label check ran `--jq` once per page of issue events, so an issue with more than one page gave several lines. Reproduced with `per_page=3` on pilot #31. The suggested `--slurp` with `--jq` is refused by `gh`; the check now pipes `--slurp` output to `jq`.
- **Taken into this plan:** the exit check runs before the container stops (it needs a running container); the firewall counters reset on every start and IPv6 drops show only in the policy line (decision 6); the spec phase needs three runs (section 3); the `claude` co-author on commits, the rule suite as evidence of the checks at merge time, traceability through `(issue: #n)`, TL;DRs on the spec and research files, session-only stops logged (section 4); the researcher's allowlist (section 5).
