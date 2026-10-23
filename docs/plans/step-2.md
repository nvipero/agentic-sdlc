# Step 2 plan: Context and spec chain

Status: approved by owner, 2026-10-23 (draft 2, after Fable review)
Spec: `specs/factory-v1-spec.md` revision 6, section 10, step 2
Date: 2026-10-23

## TL;DR

- **What gets built:**
  - Three roles as Agent Skills with thin role definitions: researcher, spec writer, spec reviewer.
  - The first part of the orchestrator: `/factory:run <issue>` takes a story from `ready-for-factory` to a spec waiting for your approval. Step 3 extends the same command to tests and implementation.
  - `/factory:context`: the researcher interviews you and writes the project context.
  - Factory definitions load as a Claude Code plugin from the read-only `/workspace/.factory`. That also answers the story worktree question for step 3.
  - Naming conventions written down: Conventional Commits and Conventional Branch.
- **Exit (spec section 10):** an approved project context for the Todo-app, and one story with an approved spec where at least one question was answered through the issue.
- **Where I need you:** approve this plan, answer the researcher's interview, write one story, answer the spec writer's questions in the issue, approve the spec, and merge PRs.
- **Most likely reason this slips:** the spec writer finds nothing to ask, because a Todo-app story is too clear. The exit criterion needs a real question. Mitigation in section 7: write the story with one deliberately open decision.

## Changes from draft 1 (Fable review, 2026-10-23)

| # | Change | Section |
|---|---|---|
| 1 | **Blocking:** commands are flat files (`commands/run.md`), because a plugin's `commands/` does not read `<name>/SKILL.md` | 3 |
| 2 | READMEs excluded from the copy into `.factory/`, and the copy step added to the new-project README steps | 3 |
| 3 | Managed settings allow only plugin and managed customization and no marketplace, so the agent cannot swap the plugin through user settings. Changed again after a test: force-enabling the plugin in managed `enabledPlugins`, as the review suggested, stops it from loading | 4 |
| 4 | Bypass mode's first-start dialog skipped in managed settings | 4 |
| 5 | Push at every stop, not only when the spec is ready | 3, 6 |
| 6 | Exit checks read the event stream, not the model's wording | 8 |
| 7 | Missing spec deviations listed: worktrees, `/factory-run` in sections 4 and 10, researcher model, return to the researcher | 6, 10 |
| 8 | Commands may use Claude Code-specific fields | 3 |

Kept by owner decision: the spec writer has Bash and commits its own work, and the review loop rules stay as written. Both are revisited if they cause problems.

## 1. Decisions in this plan

Technical choices I made, with the reason. Each one can be overruled.

| # | Decision | Reason |
|---|---|---|
| 1 | `.factory/` is a Claude Code plugin named `factory`, loaded from `/workspace/.factory` with `CLAUDE_CODE_PLUGIN_DIRS` | Keeps the spec's layout. The absolute path works from any directory, including a story worktree |
| 2 | Commands are namespaced: `/factory:run`, `/factory:context`. Role agents are `factory:spec-writer` and so on | Claude Code namespaces every plugin component. The spec's `/factory-run` becomes `/factory:run` (spec change, section 6) |
| 3 | The researcher interview runs in the main session, not in a subagent | Subagents cannot ask the user questions: "AskUserQuestion" is removed from subagents (sub-agents docs) |
| 4 | **Each producing role commits its own work.** The spec writer is a subagent with Bash and commits only its own paths. The orchestrator never writes or commits role files: it creates the branch, pushes, sets labels and posts comments | Each round is its own commit with the role in it, so the history shows who changed what. An orchestrator edit to a spec would be a separate commit, not mixed into the writer's work. The same model works in step 3, where test writer and implementer need Bash to run tests |
| 4b | The spec reviewer is a subagent with read tools only (Read, Grep, Glob) | It produces no files and needs no Bash. "Must not edit files" then holds at the tool level. The orchestrator records its findings in the issue |
| 5 | Model per role comes from `.factory/config.yaml`. The command passes it on each subagent call | The docs list the per-call `model` parameter first in the resolution order. The config stays the single place to change a role's model |
| 6 | Bypass mode is the default through managed settings: `permissions.defaultMode: "bypassPermissions"` | The spec says Claude Code runs without per-command prompts. Managed settings make that true without relying on a start flag. Deny rules still apply in bypass mode |
| 7 | The story branch is `feat/issue-<n>-<slug>`. The spec is committed and pushed there, with no PR yet | Spec section 5: one branch per story, spec first. Agents open no PRs before step 3 (spec section 12) |
| 8 | The project context goes to `main` through a PR you open and merge from the branch `chore/project-context` | Spec section 5: the context is approved before stories are accepted. You open the PR, so no agent opens one in step 2 |

## 2. Naming conventions (first change)

- **Commits:** [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/): `type(scope): description`, with the types `feat`, `fix`, `docs`, `chore`, `test`, `refactor`. The history of both repos already follows it.
- **Branches:** [Conventional Branch 1.1.0](https://conventionalbranch.org/): `<type>/<description>`, lowercase letters, digits and hyphens. `feat/` and `fix/` are allowed aliases, and `main` takes no prefix.
- **Story branches:** `feat/issue-<n>-<slug>` for stories, `fix/issue-<n>-<slug>` for bugs, `chore/issue-<n>-<slug>` for chores.
- **Where it is written:** the spec (new subsection in section 5), the project template's `CLAUDE.md`, and the factory README.
- **One fix:** the exit check's probe branch `exit-check-<time>` becomes `chore/exit-check-<time>`, and the local `exit-check-rebuild` becomes `chore/exit-check-rebuild`.
- **Not enforced yet:** a commit message check needs Actions, which stays off until step 4. Until then the conventions are instructions, checked by the code review of each PR.

## 3. What I create, and where

### Factory repo (`agentic-sdlc`), branch `feat/step-2-context-and-spec`

```
skills/researcher/SKILL.md            interview, context and glossary format, open questions
skills/spec-writer/SKILL.md           understanding check, spec format, questions vs assumptions
skills/spec-reviewer/SKILL.md         review checklist and finding format
agents/spec-writer.md                 tools: Read, Grep, Glob, Write, Edit, Bash, Skill, WebSearch, WebFetch; skill preloaded
agents/spec-reviewer.md               tools: Read, Grep, Glob, Skill, WebFetch; skill preloaded
commands/run.md                       /factory:run <issue>, spec phase only
commands/context.md                   /factory:context
templates/project/.factory/.claude-plugin/plugin.json   name "factory"
templates/project/.devcontainer/managed-settings.json   plugin dir, plugin-only customization, no marketplaces, bypass default
templates/project/CLAUDE.md           naming conventions, how to start
templates/project/.factory/config.yaml   rework_resets added (section 6), researcher model comment
scripts/exit-check.sh                 step 2 checks added (section 8)
docs/plans/step-2.md                  this plan
docs/verification/step-2.md          evidence
```

- Role skills follow the conventions in `skills/README.md` (portable fields only).
- **Commands are flat Markdown files** in the plugin's `commands/`: `commands/run.md` becomes `/factory:run`. A plugin's `commands/` reads only flat files, so a `commands/run/SKILL.md` would not load (plugin components docs, found in review).
- **Commands are Claude Code-specific,** unlike role skills. They may use Claude-only fields such as `disable-model-invocation: true` and `argument-hint`, so that only you start them.
- Role definitions in `agents/` set tools and the preloaded skill, and leave `model` to the call (decision 5).
- **Commit rule for every producing role** (written in each producing skill and in the template's `CLAUDE.md`):
  - Stage only the role's own paths by name (`git add specs/<file>`), never `git add -A` or `git add .`.
  - Conventional Commits message, with a `Factory-Role: <role>` trailer, for example `Factory-Role: spec-writer`.
  - Commit, do not push. The orchestrator pushes at every stop (questions, dispute, ready), so the branch on GitHub changes only at handoff points and nothing waits unpushed in the workspace.
  - No comments, labels or other GitHub calls. Those belong to the orchestrator.
- The researcher has no file in `agents/`: every file there becomes a subagent, and the researcher runs in the main session (decision 3). `/factory:context` loads its skill.

### Getting definitions into a project

The project's `.factory/` is a copy of the factory's `skills/`, `agents/` and `commands/` (spec: "copied skills, agents, commands"). The copy goes to the project through a PR you merge, then you pull the host clone, as with every change to factory paths:

```sh
rsync -a --delete --exclude README.md skills agents commands templates/project/.factory/ ../<project>/.factory/
```

- `README.md` is excluded, because every Markdown file in a plugin's `agents/` or `commands/` loads as an agent or a command.
- The same command goes into the README's steps for a new project. `templates/project/` alone has an empty `.factory/`.

The README documents this command. A sync script is not worth it in v1 (spec section 12: template drift is accepted).

### Project repo (`sdlc-pilot`)

- A PR with the new `.factory/`, `.devcontainer/` and `CLAUDE.md` from the template. You merge it and pull.
- Then, through the factory itself: `docs/product-context.md`, `docs/glossary.md` (your PR), one story issue, and its spec on a story branch.

## 4. Discovery and the story worktree question

- **Loading:** managed settings set `CLAUDE_CODE_PLUGIN_DIRS=/workspace/.factory` in `env`. The variable exists from v2.1.280, and the image pins 2.1.308.
- **Managed `env`:** tested on 2026-10-23 with the step 1 image in a container without network: managed `env` loads the plugin from `/workspace/.factory`, and the `init` event lists `factory`, the command `factory:run` and the agent `factory:spec-reviewer`.
- **The plugin cannot be swapped.** The agent can write user settings in the Claude volume. Tested with a same-named plugin in `~/.claude/skills/factory` and `"factory@inline": false` in user settings:

  | Managed settings | Result |
  |---|---|
  | Plugin directory only | The impostor loads in place of the factory plugin |
  | Plus `strictPluginOnlyCustomization: true` and `strictKnownMarketplaces: []` | No `factory` plugin loads. The agent can switch the factory off, but cannot replace it |
  | Plus `enabledPlugins: {"factory@inline": true}` | The real plugin does not load either: "--plugin-dir copy of "factory" ignored: plugin is locked by managed settings" |

  Managed settings therefore use the second row. `strictPluginOnlyCustomization` blocks skills, agents, hooks and MCP servers that do not come from a plugin, managed settings or Claude Code itself. The empty marketplace allowlist stops the agent from installing a same-named plugin from GitHub, which the firewall allows. `disableSideloadFlags` is not used, because it would also reject `CLAUDE_CODE_PLUGIN_DIRS`.
- **What remains:** an agent that disables the factory plugin in user settings leaves the next session without `/factory:*` commands. That is visible at once, and nothing else loads in its place.
- **Bypass mode's first-start dialog** is skipped with `skipDangerousModePermissionPrompt` in managed settings, so nothing is written to user settings for it.
- **Why this is not a boundary:** an agent with Bash can start its own `claude --plugin-dir` anyway. What matters is that the definitions it reads are read-only and that a subagent cannot change what the main session loaded.
- **Plugin subagent limits:** the docs say plugin subagents ignore `hooks`, `mcpServers` and `permissionMode`. None of the roles needs them.
- **Story worktrees (step 3):** the plugin path is absolute, so a session in a worktree loads the same read-only definitions. What a worktree still has is its own `CLAUDE.md` and `.claude/` from git, which an agent could change. Step 3 decides whether sessions run only from `/workspace` or worktrees get their own read-only mounts. Step 2 uses no worktrees: the spec writer works in `/workspace` on the story branch.

## 4b. Research and sources (owner direction, 2026-10-23)

- **Research before asking.** Roles ask the owner only what research cannot answer and the owner can. A question the owner could not answer, or one research could have answered, is a review finding.
- **Research is trusted when it was actually done.** Every claim in the context carries a source tag: `(owner)`, `(material: …)`, `(standard: <URL>, read <date>)`, or `(practice: <URL>; <URL>, read <date>)` for best practice that two independent sources agree on, with a search for counter-sources. The spec writer may rely on these.
- **Unconfirmed:** a single source, a blog, a contested point, a page that could not be read, and anything known only from memory. These go to a separate "Research, not confirmed" section, and the spec writer never relies on them. Merging the context does not confirm them.
- **Facts and decisions are separate.** A decision that follows from a standard or a clear practice is recorded as `Decision (researcher, from <tag>)`, visible in the PR.
- **What the network allows** (tested on 2026-10-23 in the sandbox): WebSearch works, because it runs on Anthropic's side and returns titles, URLs and a summary. WebFetch reads pages on GitHub-hosted addresses, including GitHub Pages sites such as semver.org, and the allowlisted hosts. Other sites, such as rfc-editor.org and MDN, are blocked. Opening them is not done: most sit behind shared CDN addresses, so one allowlisted site would open thousands of others.
- **Tools:** the main session (researcher) and the spec writer get WebSearch and WebFetch. The spec reviewer gets WebFetch only, to check that a cited source says what the spec claims.
- **Backlog:** a separate research container with open web access and no token or project files, if too much stays unconfirmed.

## 5. `/factory:context`

1. Runs in the main session with the researcher skill.
2. Interviews you: purpose, users, domain terms, constraints, non-goals (spec section 5). One topic at a time, and it says when it has enough.
3. Writes `docs/product-context.md` and `docs/glossary.md`. Uncertainties are listed as open questions, never as facts.
4. Commits on `chore/project-context` under the commit rule with `Factory-Role: researcher`, then pushes and prints the link for opening the PR.
5. You read, correct and merge. The context counts as approved once it is on `main`.

## 6. `/factory:run <issue>`, spec phase

Each run reads the issue's state and does the next step. Running it again after you answer continues from there.

1. **Checks before work:**
   - The issue has `ready-for-factory` and `user-story`, `bug` or `chore`.
   - `docs/product-context.md` exists on `origin/main`. Without it the story is refused (spec section 5).
   - The workspace is fetched and the story branch is created or checked out from `origin/main`.
2. **Trusted input:** only the issue body and comments written by the repository owner are passed to the roles. Other authors are skipped and reported. This is defence in depth on top of the interaction limit.
3. **Spec writer** (subagent): writes the "Problem and why" section first, traced to the project context. If it cannot, it returns questions instead of a spec. When the questions show that the project context itself is wrong or incomplete, the orchestrator says so in the issue and asks you to run `/factory:context` again; that is how a story "returns to the researcher" (spec section 5) in step 2. Otherwise it writes `specs/<issue>-<slug>.md` with the sections from spec section 5 and commits it under the commit rule (section 3).
4. **Spec reviewer** (subagent, separate context): checks ambiguity, missing edge cases, testability and consistency with the context. Returns findings.
5. **Producer and reviewer loop:** the orchestrator posts the findings to the issue and passes them to the spec writer, which fixes the spec and commits the fix. The orchestrator never fixes a spec itself: if it thinks the spec must change, it returns the spec to the writer with a reason, like any other handoff. The review loop rules below apply.
6. **Review loop rules** (from `config.yaml`, the same in step 3):
   - **A loop ends in only two ways:** the reviewer approves the latest version, or the work escalates to you with `dispute`. Running out of rounds never approves anything.
   - **Fixes are targeted:** the producer makes the smallest change that resolves each finding and nothing unrelated. This is written in every producing skill.
   - **The reviewer classifies each round's change** as a targeted fix or a rework, with a reason. A rework means that the scope or the acceptance criteria changed (in step 3: the change reaches beyond the findings).
   - **A rework is a new version:** the reviewer reviews it in full, not only the fixes, and the round count starts again. This happens at most `rework_resets` times (1). A second rework escalates to you, because repeated rewrites usually mean the story or the approach is wrong.
   - **Limits:** at most `max_rounds` rounds (4) per version, and escalation after `escalate_when_no_progress_for` rounds (2) that repeat the same findings.
   - **Visible size:** each round's handoff comment includes the change size from `git diff --stat`, so a rework labelled as a fix shows in the issue.
7. **Questions:** the main session posts them as one issue comment that starts with a TL;DR, and adds `needs-human`. On the next run, your answers are passed to the spec writer, and `needs-human` is removed.
8. **Ready:** when the reviewer approves and no questions are open, the orchestrator pushes the branch (it pushes at every stop) and a comment links to the spec. You add `spec-approved`.
9. **Handoffs:** every step leaves a short comment in the issue, so the chain is visible (spec principle 10).

## 7. Exit: the Todo-app run

1. You run `/factory:context` and answer the interview. I take no part in your answers.
2. You merge the context PR. No host pull is needed, because `docs/` is not a factory path.
3. You write one story with the issue form and add `ready-for-factory`.
   - **The risk:** a Todo-app story can be clear enough that an honest spec writer asks nothing. The exit criterion needs a real question, not a forced one.
   - **Mitigation:** leave one product decision open in the story, for example what happens to completed items, or whether items have due dates.
4. You run `/factory:run <n>`, answer the question in the issue, run it again, and add `spec-approved`.

## 8. Exit check and evidence

### Scripted (added to `scripts/exit-check.sh`)

Checks read the event stream of `claude -p --output-format stream-json --verbose`, not the model's wording:
- **The plugin loads:** the `init` event lists `factory` under `plugins`, with no `plugin_errors`, and lists the agents `factory:spec-writer` and `factory:spec-reviewer` and the command `/factory:run`.
- **The plugin cannot be swapped:** with `"factory@inline": false` in user settings and a same-named plugin in `~/.claude/skills/factory`, the next session loads no `factory` plugin at all, and the impostor's commands are absent.
- **Bypass mode is the default** without a start flag, and the merge deny rule still holds.
- **The reviewer writes nothing:** asked to write a file, the reviewer's run has no `Write`, `Edit` or `Bash` tool use under its `parent_tool_use_id`.
- `.factory/` stays read-only, including the plugin manifest.
- The existing step 1 checks still pass.

### From the real run (`docs/verification/step-2.md`)

- The merged context PR.
- The story issue: the question comment, your answer, the handoff comments and the labels in order.
- The spec on the story branch: its "Problem and why" section, with the parts that trace to the context marked.
- The story branch diff touches only `specs/`, and every commit on it carries `Factory-Role: spec-writer`. A commit without a role trailer, or one that touches other paths, is a finding.
- The reviewer's findings and how the writer answered them.

## 9. Step 1 backlog: what I take now

The step 1 rule was to fix only blocking findings. These touch files that step 2 changes anyway, so they are cheap now.

| Item | Take now | Why |
|---|---|---|
| Stdin of `up.sh <cmd>` and `-t` for init and probe | Yes | Interactive sessions start through `up.sh` |
| `FACTORY_REPO_URL` only for the workspace init | Yes | Same lines |
| Messages for a failed Actions call and a diverged clone | Yes | Small |
| README: Actions off on the factory repo too | Yes | Docs only |
| Stale comment in `devcontainer.json` | Yes | Docs only |
| Workflow-push probe in the exit check | Yes | Proves the token has no Workflows permission |
| Behind-clone test checks its own setup | Yes | Same section of the exit check |
| IPv6 fallback fails on any non-loopback IPv6 address | Yes | One line |
| Copy container mounts the workspace read-only | Yes | Makes "was not changed" structural |
| Session signals without a terminal | No | Interactive sessions have a terminal |
| Token in the docker client's environment | No, accepted | Same-user processes can reach the container through Docker anyway |
| Exit check robustness (fallback, `expect` timeout), verification cost, duplicated filter | No | No effect on safety or the factory |

## 10. Spec changes (revision 7)

- Section 5: naming conventions (section 2 of this plan).
- Section 6: `/factory:run` and `/factory:context` instead of `/factory-run`. The researcher runs in the main session.
- Section 4: `.factory/` is a Claude Code plugin.
- Sections 9 and 13: the test project topic is a Todo-app.
- Sections 4 and 10: `/factory-run` also appears in the repository layout and in step 3.
- Section 4: "Each story gets its own git worktree" does not apply in step 2, which works on the story branch in `/workspace`. Step 3 decides the worktree setup.
- Section 4: `roles.researcher.model` in `config.yaml` has no effect, because the researcher runs in the main session with the session's model. The config entry stays, with a comment, and `/factory:context` says which model the session uses.
- Sections 5 and 6: the researcher researches as well as interviews, every context claim carries a source tag, and roles research before asking (section 4b).
- Section 4: `config.yaml` gets `rework_resets`, and section 5 gets the review loop rules (section 6 of this plan). The spec shows the config file in full, so it must match.

## 11. Known limitations in step 2

- **Write paths and the commit rule are instructions until step 4.** The spec writer can write anywhere in the workspace, and with Bash it could also stage other files, comment or change labels with the token. Removing Bash would not have been a boundary either, because the main session has Bash. Per-path limits per subagent are not documented, and the PreToolUse hook the docs suggest is ignored for plugin subagents. The path ownership guard in step 4 enforces this. Until then the exit check shows that the story branch only touches `specs/`.
- **The orchestrator could still edit a spec.** Nothing at tool level prevents it, because the main session needs Write and Bash. The commit rule makes it visible instead: such an edit is a commit without the spec writer's trailer.
- **The role trailer is not proof of authorship.** Any session can write any trailer. It makes honest mistakes visible, not deliberate ones. A separate agent identity in step 4 does not change this either, since all roles share it.
- **Same session, different roles:** the main session holds the orchestrator and the researcher. The researcher has no reviewer in the spec, because you approve the context. The researcher commits the context under the same commit rule with `Factory-Role: researcher`.
- **The rework classification is the reviewer's judgement.** A reviewer that calls a rework a targeted fix skips the full review. The change size in the handoff comment shows it to you, but nothing prevents it.
- **GitHub Pages is reachable.** Step 1's "all of GitHub is reachable" includes every GitHub Pages site, also on custom domains. Pages gives site owners no request logs, so it is a weak channel out, and inbound content from any public repository was already readable.
- **WebSearch queries leave through Anthropic.** A query reaches the search backend without passing the firewall. Everything an agent sees already goes to Anthropic, so the extra channel is the search provider.
- **The Claude volume is writable by the agent.** A session could change user-level settings in `/home/node/.claude`. Managed permission rules and the managed plugin settings (section 4) win over them, but other user settings, such as `~/.claude/CLAUDE.md`, still apply to later sessions. This was true in step 1 too.

## 12. Where I need you, and what can go wrong

- **You:** approve this plan, do the interview, write the story, answer the question, approve the spec, and merge the factory PR, the pilot PR and the context PR.
- **I do on my own:** everything else, and I report results and deviations.
- **Most likely reasons this slips:**
  - No real question in the spec phase (section 7).
  - The plugin does not load from managed `env` (section 4 fallback).
  - Interview quality: if the researcher asks too much or too little, the skill needs a round of tuning. That is expected in this step.
