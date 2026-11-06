# Purpose and principles

## Purpose

A reusable, project-agnostic setup in which AI agents take a user story from idea to a reviewable preview. The human sets goals and priorities, validates specs and accepts results. Agents research, specify, test, implement and review each other's work. Deterministic tools act as hard gates.

The factory is not yet optimised for speed, parallelism or visuals.

## Principles

Changing one requires an owner decision.

1. **GitHub is the single source of truth.** Stories are GitHub Issues, specs are Markdown files in the project repo, implementation happens in pull requests, status lives in labels and a GitHub Projects board (a view over the issues).
2. **Understanding comes before specification.** No agent writes a spec it cannot justify. Every spec states in the agent's own words what problem the story solves and why, traced to the project context. If the agent cannot do that, it asks the human instead.
3. **Every producing agent has a reviewer** with its own context. Producer and reviewer never share a session.
4. **Least privilege.** Every agent has the narrowest permissions that still let it do its role: limited tools, limited write paths, a repo-scoped token, and a network allowlist.
5. **Limits must be out of the agent's reach.** A rule an agent can edit is not a limit. Restrictions are enforced by the container, the file system, GitHub and CI, not only by instructions or agent-editable settings.
6. **Agents never modify factory definitions** inside a project repo. Changes to the factory happen in the factory repo through a pull request the human approves.
7. **Deterministic gates are not replaced by agents.** Lint, type checks, tests and security scans decide whether a change can merge. Agents cannot change gates.
8. **Acceptance tests are written before implementation** by a different agent than the implementer. The implementer cannot change them.
9. **Code is persistent and layered.** Changes are scoped to the story. Regenerating large parts of the codebase is a separate, human-approved decision.
10. **Work can move upstream as well as downstream.** Any role may return work to an earlier role with a reason. All handoffs go through the orchestrator and are recorded in the issue or PR, so the full chain is visible when the human steps in. The chain lives in one status comment that is edited in place; new comments are posted only when they have value to the human or another agent (questions, disputes, a result ready for review), because every comment is a notification.
11. **Disputes escalate on lack of progress,** not on a fixed round count alone.
12. **The human's attention is the scarcest resource.** Humans are pulled in only at defined points. When they are, they get a focused list of what deserves their judgement, not everything.
13. **Text is sized for its reader.** Output for humans is short enough to actually read, and a question to the human carries only the question. A pull request description or document longer than about 15 lines, or with more than two sections, starts with a TL;DR as a quote block (`> **TL;DR:** ...`, owner, 2026-10-31); a shorter one is plain text, because a TL;DR over a few lines only repeats them (owner, 2026-11-06). Issue comments do not need one. Output for agents may be as detailed as needed.
14. **Role knowledge is portable.** Each role's know-how lives in an Agent Skill (agentskills.io format). Role definitions are thin wrappers that choose the model, tools and skill, so a role can move to another model or tool later.
15. **Trust, but verify.** When a check after the fact is cheap, it is added even if an earlier control (permissions, rules, gates) should already be enough. Controls are layered, not either-or (owner decision, 2026-10-30).
