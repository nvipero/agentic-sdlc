# History

## V1

V1 set out to prove that one user story can travel from a GitHub issue to a merged pull request with agents doing the specifying, testing, implementing and reviewing, and the human only setting direction, answering questions, settling disputes and accepting the result. It was specified on 2026-10-13, approved on 2026-10-21 and done on 2026-10-31. The spec's last revision is [`specs/factory-v1-spec.md` at 5758ab5](https://github.com/nvipero/agentic-sdlc/blob/5758ab5/specs/factory-v1-spec.md); the docs replaced it on 2026-11-06.

Each step ended with an exit check, and the next started only after the owner had seen the result.

| Step | Exit criterion | Evidence |
|---|---|---|
| 1. Foundations: factory repo, template, protections, dev container, start script, token | An agent inside the container cannot modify factory definitions, reach non-allowlisted hosts, see anything outside the project workspace, or push directly to `main` | [Sandbox foundations](evidence/sandbox-foundations.md) |
| 2. Context and spec chain: researcher, spec writer, spec reviewer, question flow | An approved project context, and one story with an approved spec where at least one question was answered through the issue | [Context and spec chain](evidence/context-and-spec-chain.md) |
| 3. Implementation chain: test writer, implementer, code reviewer | The story reaches a PR with passing local tests, a reviewer approval and a "Where to look" section | [Implementation chain](evidence/implementation-chain.md) |
| 4. Gates, preview, and the GitHub App as the agents' identity | A PR that breaks any gate cannot be merged, every PR marked ready gets a preview link, and the agent identity cannot merge a PR without the owner's approval | [Gates and App identity](evidence/gates-and-app-identity.md) |
| 5. First full run | Definition of done met and problems recorded | [First full run](evidence/first-full-run.md) |

Definition of done for v1:

- A story written by the human reaches a merged PR without the human editing code.
- The human was asked only at defined points. Each pull request description and document longer than about 15 lines started with a TL;DR, and each question to the human carried only the question.
- The spec's problem and why section is traceable to the approved project context.
- All gates ran and were required for merge.
- No agent modified acceptance tests, factory definitions or gates.
- No agent merged a pull request.
- No agent accessed anything outside its container workspace or allowlisted network.
- Observed problems are written down for the next iteration.

## After v1

| Date | Change | Evidence |
|---|---|---|
| 2026-10-31 | Deployment of `main` to production | [Production deploy](evidence/production-deploy.md) |
| 2026-10-31 to 11-03 | Running the paths not yet exercised | [Untested paths drill](evidence/untested-paths-drill.md) |
| 2026-11-05 to 11-06 | Choices in specs, current behaviour from `main` | [Spec choices and sources](evidence/spec-choices-and-sources.md) |
| 2026-11-06 | Backlog moved to GitHub Issues; docs replaced the versioned spec; the v2 isolation plan dropped in favour of a real project | [#51](https://github.com/nvipero/agentic-sdlc/pull/51), [#19](https://github.com/nvipero/agentic-sdlc/issues/19) |
| 2026-11-12 | The `assist` plugin: the roles for one task in an existing repository, tried on a client task | [Assist trial](evidence/assist-trial.md), [#72](https://github.com/nvipero/agentic-sdlc/pull/72) |

Plans for these steps were removed with the spec; they are in git history at 5758ab5 under `docs/plans/`. From now on a plan lives in its backlog issue and the evidence in its pull request.

The evidence documents cite the spec's sections and backlog item numbers of their time: the spec is linked above, and each backlog issue names its old item number.
