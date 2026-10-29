# Step 2 verification

Date: 2026-10-23 to 2026-10-29. Plan: [docs/plans/step-2.md](../plans/step-2.md), approved 2026-10-23.
Host details in the outputs below are redacted: home path → `~`, private IPs → `<private-ip>`.

## TL;DR

- **Exit criterion met** (spec section 10): the Todo-app project context is approved (sdlc-pilot PR #27, merged), and issue #29 has an approved spec where the owner answered a question in the issue.
- **Scripted exit check:** all 86 checks pass, none skipped, against sdlc-pilot main with PR #25 merged.
- **What worked in the real run:** the understanding check traced every claim to the context; a research request went to the researcher and came back with two independent sources and the unreadable ones marked unconfirmed; the review loop ran two rounds, the writer disagreed with one finding and the reviewer withdrew it; every commit touched only its role's paths.
- **What did not:** the first story produced no question, because the story's own wording answered it. The orchestrator missed an owner comment when run twice in one session. Issue comments were too many and too long. Twelve observations are listed below, to be fixed before step 2 is closed.

## Exit criteria and evidence

| Criterion | Evidence |
|---|---|
| Approved project context | PR #27 (`chore/project-context`), merged by the owner on 2026-10-23. One commit, only `docs/product-context.md` and `docs/glossary.md`, `Factory-Role: researcher` |
| One story with an approved spec | Issue #29 "Remove a task I no longer need", label `spec-approved`. Spec `specs/29-remove-task-no-longer-needed.md` on `feat/issue-29-remove-task-no-longer-needed` |
| At least one question answered through the issue | Issue #29: the spec writer asked how removal is protected (confirm first, undo window, or both). The owner answered in a comment (option B), and the next run applied it |

## Real run

### Project context (`/factory:context`, PR #27)

- The interview ran in the main session, one topic at a time, with a read-back after each.
- **Sources:** owner statements tagged `(owner)`. `localStorage` facts read from MDN's content repository on GitHub, and WCAG 2.2 from the W3C Editor's Draft on GitHub Pages: both reachable through the firewall's GitHub ranges. The WHATWG standard could not be reached and went to "Research, not confirmed".
- **Owner's definition kept:** the owner defined a swimlane as one lane per status, which differs from common Kanban usage. The researcher recorded the owner's meaning and marked the common usage as unconfirmed.
- **Five open questions** left for stories (accessibility level, blocked storage, task contents and editing, allowed status moves, supported browsers).

### Issue #28 "Add a task and move it between statuses" (approved, no question)

- One commit, `specs/28-add-task-move-statuses.md`, role line present.
- **No question was asked.** The acceptance criterion "I can move a task to another status" answered the open question about allowed moves before the spec writer saw it. The writer assumed any-to-any moves from that wording, and the reviewer noted it as non-blocking (R1-2). The story was written in this session, so the leak was ours, not the factory's.
- The orchestrator reported that the spec writer read files with `cat` through Bash, outside its allowed git-only use. Harmless, and visible.

### Issue #29 "Remove a task I no longer need" (approved, question answered)

| Step | Commit | Paths | Role line |
|---|---|---|---|
| Research request answered | `92e4611` | `docs/research/29-task-removal-safeguard.md` | researcher |
| Owner's answer applied | `e5427a3` | `specs/29-remove-task-no-longer-needed.md` | spec-writer |
| Review round 1 fixed | `3412c3c` | `specs/29-remove-task-no-longer-needed.md` | spec-writer |

- **Research:** best-practice claims cite two independent sources read in full (Microsoft's UX guidelines on GitHub and GitHub's Primer). Nielsen Norman Group and Smashing Magazine could not be read and were marked unconfirmed. The researcher's own reading went to "Open questions", not into the answer.
- **Question:** one product decision with three options and the writer's recommendation. It was combined with a context problem and an assumption list in one comment (observation 10).
- **Review:** round 1 found one blocking issue (an untestable focus criterion) and three non-blocking. The writer fixed the blocking one and disagreed with R1-3 with a reason; round 2 withdrew R1-3 and approved, change class `targeted`.
- **Owner's answer:** the comment the owner posted was an example written in this session that already contained option B. The spec records "the owner chose" B. The owner reviewed the spec and approved it with B. Lesson: example answers given to the owner must not contain the decision.
- **State across runs:** after `/clear`, a re-run picked up the owner's comment and continued. Without `/clear`, the same session reported no new comment (observation 9).

### Other confirmations

- **Bypass first-start dialog:** not shown when the session started; managed `skipDangerousModePermissionPrompt` works.
- **Skill preload:** the reviewer's output followed its skill's return format (finding ids, change class), so the `skills:` preload in plugin agents works. The exit check had left this open.
- **Workflows permission:** the token's push of a workflow file was refused with "refusing to allow a Personal Access Token to create or update workflow". This was an assumption before step 2.

## Observations from the real run (to fix before closing step 2)

1. **Language is not configurable.** Agents spoke English at first. Repository content (context, specs, research, issues) stays English; the conversation language becomes a setting, Finnish by default.
2. **Open questions were forced into option lists,** with options that said "choose Other", which the UI does not show. Read-backs need only "correct", with corrections typed. The researcher also offered "pilot only, no product": the factory's own purpose does not belong in the product context.
3. **The researcher asked which language documents use.** That is a factory setting, not a product question.
4. **Source tags are too coarse.** MDN (documentation) and a W3C Editor's Draft were both tagged `standard`. Tags must tell a normative standard, official documentation and a draft apart.
5. **A factory setting landed in the product context** ("documentation is written in English"). Follows from observation 3.
6. **Open questions in the context were recorded correctly.** No fix needed.
7. **The role line is not a git trailer.** Claude Code adds its own `Co-Authored-By` paragraph after a blank line, so git parses only that paragraph as trailers; `git log --format=%(trailers:key=Factory-Role)` finds the role on one commit of four. The orchestrator's text check still works; a step 4 gate reading trailers would not.
8. **A question and a context problem came in one comment.** Resolved by observation 10.
9. **The orchestrator must read the issue at the start of every run.** Run twice in one session, it relied on its memory and missed the owner's comment. Confirmed: after `/clear` it found it.
10. **A question comment contains only the question.** No context problems and no assumption lists in it. Agents make assumptions themselves; they are listed in the "spec ready" comment.
11. **No TL;DR in issue comments.** TL;DR belongs in pull request descriptions.
12. **No progress-log comments.** Issue #29 got 12 comments, each a notification. Only comments with value to the owner or another agent are posted; the run's state and chain go into one status comment edited in place.

The owner decided that observations 10 to 12 refine spec principles 10 (visible handoff chain) and 13 (TL;DR for human output).

## Deviations from the plan

- **Managed `enabledPlugins` is not used.** The review suggested force-enabling the plugin; a test showed it locks out the `CLAUDE_CODE_PLUGIN_DIRS` copy ("--plugin-dir copy of "factory" ignored: plugin is locked by managed settings"). `strictPluginOnlyCustomization` and an empty marketplace allowlist are used instead.
- **Research requests** (plan decision 9) were added after the plan was approved: the spec writer has no web tools and asks the researcher through the orchestrator.
- **Research reach:** WebSearch works; WebFetch reaches GitHub-hosted pages, including GitHub Pages and documentation mirrored in GitHub repositories. The layered sandbox (plan section 13) is the next design item.
- **Review before the pilot PR:** a code review of the step 2 diff found ten issues before anything reached sdlc-pilot. Eight were fixed, one is a known limitation until step 4 (forged trusted input), and none were blocking under the step 1 definition.

## Scripted exit check (`scripts/exit-check.sh`, steps 1 and 2, redacted)

All 86 checks pass, none skipped, against `sdlc-pilot` main with PR #25 merged.

- **Reviewer skill preload is still unproven.** The reviewer did not load its skill with the Skill tool, so either the `skills:` preload worked or the skill was not loaded. The real run shows which, from whether the reviewer's output follows the skill's return block.
- **The reviewer write test is weak evidence.** Asked to write a file, the reviewer made no tool calls at all. The check proves it wrote nothing; the tool lists prove it had no write tool.

```text
# Exit check (steps 1 and 2)
date: 2026-10-23T16:46:01Z
project: nvipero/sdlc-pilot  factory: nvipero/agentic-sdlc
devcontainer tree: dfb6f6a5da77b2e8374c738f02a70ad55fc2c3f8
claude: 2.1.308 (Claude Code)

## Factory definitions cannot be modified
PASS  write to .factory/ is refused — touch: cannot touch '/workspace/.factory/exit-check-probe': Read-only file system
PASS  write to .claude/ is refused — touch: cannot touch '/workspace/.claude/exit-check-probe': Read-only file system
PASS  write to .github/ is refused — touch: cannot touch '/workspace/.github/exit-check-probe': Read-only file system
PASS  write to .devcontainer/ is refused — touch: cannot touch '/workspace/.devcontainer/exit-check-probe': Read-only file system
PASS  write to CLAUDE.md is refused — bash: line 1: /workspace/CLAUDE.md: Read-only file system
PASS  managed settings are readable by the agent (Claude Code skips unreadable ones) — ["Bash(gh pr merge *)","Bash(gh api *merge*)","Bash(gh api *Merge*)"]
PASS  managed settings are not writable — bash: line 1: /etc/claude-code/managed-settings.json: Permission denied
PASS  allowlist in image is not writable — bash: line 1: /etc/factory/allowlist.txt: Permission denied
PASS  scripts/up.sh is not present — absent
PASS  .git is on the workspace volume, not the host — /dev/vda1[/var/lib/docker/volumes/sdlc-pilot-workspace/_data] ext4
PASS  overlays are hidden from git — clean
PASS  sudo allows only the firewall script — /usr/local/bin/init-firewall.sh
PASS  iptables as agent is refused — iptables v1.8.11 (nf_tables): Could not fetch rule set generation id: Permission denied (you must be root)
PASS  no claude binary under /home/node — -rwxr-xr-x root root

## Network allowlist
PASS  https://example.com is blocked — curl: (7) Failed to connect to example.com port 443 after 2 ms: Could not connect to server
PASS  https://google.com is blocked — curl: (7) Failed to connect to google.com port 443 after 16 ms: Could not connect to server
PASS  https://1.1.1.1 is blocked — curl: (7) Failed to connect to 1.1.1.1 port 443 after 0 ms: Could not connect to server
PASS  outside DNS resolver is blocked — ;; communications error to 8.8.8.8#53: host unreachable
PASS  host gateway is blocked — curl: (7) Failed to connect to 172.17.0.1 port 80 after 0 ms: Could not connect to server
PASS  host.lima.internal is blocked by the firewall — curl: (7) Failed to connect to host.lima.internal port 80 after 0 ms: Could not connect to server
PASS  host.docker.internal is blocked by the firewall — curl: (7) Failed to connect to host.docker.internal port 80 after 0 ms: Could not connect to server
PASS  IPv6 loopback is open — http://[::1] 200
PASS  https://api.anthropic.com is reachable (404 expected for the bare host) — 404
PASS  https://api.github.com/zen is reachable (authenticated, 200 expected) — 200
PASS  https://registry.npmjs.org/ is reachable (200 expected) — 200

## Network stays closed when the firewall fails
PASS  firewall exits non-zero on resolution failure — init-firewall: FAILED (exit 1): network closed except loopback
PASS  api.github.com unreachable after failed firewall run — curl: (6) Could not resolve host: api.github.com
PASS  firewall marker removed after failure
PASS  agent cannot pass an allowlist override through sudo — init-firewall: OK: 82 allowed networks
PASS  sudo refuses the firewall script with arguments — sudo: a password is required
PASS  network restored by a normal firewall run (authenticated, 200 expected) — 200
PASS  exec guard refuses without the firewall marker — factory-exec: REFUSING: firewall marker missing

## Restarts: no automatic restart, firewall on every start
PASS  restart policy is 'no'
PASS  firewall marker is on tmpfs — tmpfs
PASS  PID 1 is docker-init (signals are forwarded)
PASS  docker restart completes without waiting for SIGKILL — 1s
PASS  after a manual docker restart: fresh marker, example.com blocked — marker from 16:46:06, example.com blocked
PASS  firewall failure at start stops the container (run without NET_ADMIN) — running=false exit=1; container-entrypoint: firewall failed; stopping container

## Visibility: nothing outside the project workspace
```
/workspace ext4 rw,relatime
/workspace/CLAUDE.md fuse.sshfs ro,nosuid,nodev,relatime,user_id=501,group_id=1000,allow_other
/workspace/.factory fuse.sshfs ro,nosuid,nodev,relatime,user_id=501,group_id=1000,allow_other
/workspace/.claude fuse.sshfs ro,nosuid,nodev,relatime,user_id=501,group_id=1000,allow_other
/workspace/.github fuse.sshfs ro,nosuid,nodev,relatime,user_id=501,group_id=1000,allow_other
/workspace/.devcontainer fuse.sshfs ro,nosuid,nodev,relatime,user_id=501,group_id=1000,allow_other
/home/node/.claude ext4 rw,relatime
```
PASS  mounts: only workspace volume, 5 read-only overlays, Claude volume — 7 mounts, 5 read-only
PASS  no host home, Docker socket or SSH keys — none
PASS  credential-like env vars: only GH_TOKEN — GH_TOKEN 

## Token on disk
PASS  token not in docker inspect (container or image)

## Agent token reach (observed behaviour)
PASS  agent token can push a branch — pushed chore/exit-check-1792773968
PASS  agent token can open a draft PR — https://github.com/nvipero/sdlc-pilot/pull/26
PASS  agent token cannot push to main (ruleset, fast-forward commit) — remote: error: GH013: Repository rule violations found for refs/heads/main.        
PASS  agent token cannot create a ruleset — gh: Resource not accessible by personal access token (HTTP 403)
PASS  agent token cannot change interaction limits — {"message":"Resource not accessible by personal access token","documentation_url":"https://docs.github.com/rest/interactions/repos#set-interaction-restrictions-for-a-repository","status":"403"}gh: Resource not accessible by personal access token (HTTP 403)
PASS  agent token cannot change repository settings — {"message":"Resource not accessible by personal access token","documentation_url":"https://docs.github.com/rest/repos/repos#update-a-repository","status":"403"}gh: Resource not accessible by personal access token (HTTP 403)
PASS  agent token cannot push a workflow file (no Workflows permission) —  ! [remote rejected] 6e78de2e03787065ad62c3e1ec53b551aadde84d -> chore/exit-check-workflow-1792773978 (refusing to allow a Personal Access T
PASS  agent token cannot push to the factory repo — remote: Permission to nvipero/agentic-sdlc.git denied to nvipero.
PASS  probe branch and PR cleaned up (closed, not merged)
PASS  merge deny rule active in bypass mode (claude -p, permission_denials) — {"tool_name":"Bash","command":"gh pr merge --help"}

## Step 2: factory plugin and roles
PASS  factory plugin loads from the read-only overlay, no plugin errors
PASS  agents and commands present — factory:researcher, factory:spec-writer, factory:spec-reviewer, /factory:run, /factory:context
PASS  bypass mode is the default without a start flag
PASS  merge deny rule holds in the default (bypass) mode, without a flag — {"tool_name":"Bash","command":"gh pr merge --help"}
PASS  plugin manifest is read-only — bash: line 1: /workspace/.factory/.claude-plugin/plugin.json: Read-only file system
PASS  an agent cannot replace the factory plugin through user settings — disabled in user settings: no factory plugin loads, the impostor is blocked
PASS  user settings restored, the factory plugin loads again
PASS  spec reviewer has no write tool — Read, Grep, Glob, Skill, WebFetch
PASS  spec writer has no web tools (research goes to the researcher) — Read, Grep, Glob, Write, Edit, Bash, Skill
PASS  spec reviewer writes nothing when asked to — tool uses inside its run: none
NOTE  reviewer skill loaded with the Skill tool during that run: no (preloaded, or not loaded)

## Protections through the API (owner login)
### nvipero/sdlc-pilot
```
visibility: PUBLIC
ruleset protect-main: enforcement=active bypass_actors=0 target=["~DEFAULT_BRANCH"] rules=["pull_request","non_fast_forward","deletion"]
interaction limit: collaborators_only until 2027-04-22T09:56:24Z
actions enabled: false
secret scanning: enabled, push protection: enabled
```
PASS  nvipero/sdlc-pilot: pull_request, non_fast_forward, deletion active on main
PASS  nvipero/sdlc-pilot: no bypass actors
PASS  nvipero/sdlc-pilot: GitHub Actions disabled
### nvipero/agentic-sdlc
```
visibility: PUBLIC
ruleset protect-main: enforcement=active bypass_actors=0 target=["~DEFAULT_BRANCH"] rules=["pull_request","non_fast_forward","deletion"]
interaction limit: collaborators_only until 2027-04-22T09:56:55Z
actions enabled: false
secret scanning: enabled, push protection: enabled
```
PASS  nvipero/agentic-sdlc: pull_request, non_fast_forward, deletion active on main
PASS  nvipero/agentic-sdlc: no bypass actors
PASS  nvipero/agentic-sdlc: GitHub Actions disabled

## Image is rebuilt when .devcontainer/ changes
PASS  rebuilt image carries the new tree label — 6c629cb36beac9108840eed7ef20589f26dd6fbc
PASS  changed managed settings are in the rebuilt image
PASS  image tree mismatch is detected (start_container then stops and refuses) — container image was built from tree 'dfb6f6a5da77b2e8374c738f02a70ad55fc2c3f8', expected '6c629cb36beac9108840eed7ef20589f26dd6fbc'
PASS  the mismatch check itself has no side effects

## up.sh fails closed
PASS  preflight refuses on unexpected visibility — up.sh: REFUSING TO START: visibility is PUBLIC, expected PRIVATE
PASS  preflight refusal leaves the running container untouched — 564e4275dce5
PASS  up.sh aborts when workspace init fails — init-workspace: GH_TOKEN is not set (start with scripts/up.sh) up.sh: REFUSING TO START: workspace init failed 
PASS  no container left running after failed start
PASS  a host clone behind origin/main is refused and not updated — 2 commit(s) behind origin/main

## Token never in a host process's arguments
PASS  GH_TOKEN= and the token value never in a host process list during start and session — 53 samples

## Workspace is never deleted automatically
PASS  an existing workspace (cloned before any marker existed) survives a restart unchanged — new container, HEAD 02029f521140, untracked file kept
PASS  unresolvable HEAD (orphan branch) is reported and the start refused — STOPPING: HEAD does not resolve (HEAD -> refs/heads/exit-check-orphan; local branches: main ). This can be an orphan branch with no commits,
PASS  the workspace with an unresolvable HEAD was left untouched — HEAD -> exit-check-orphan, main and untracked file intact
PASS  reset-workspace without a terminal refuses and changes nothing (report shows HEAD and ignored files) — current HEAD: exit-check-orphan at no commits (orphan or unborn branch)
PASS  reset-workspace with a wrong repository name refuses and changes nothing
PASS  reset-workspace with confirmation archives the old workspace intact — sdlc-pilot-workspace-archive-20261023T164826Z-36955: orphan HEAD, untracked and ignored files kept, completion marker present
PASS  the new workspace is a fresh clone of origin/main — f07eae8ca415, clean
NOTE  reset-workspace archived the project's workspace to sdlc-pilot-workspace-archive-20261023T164826Z-36955 (kept on purpose; remove it with: docker volume rm sdlc-pilot-workspace-archive-20261023T164826Z-36955)

## Restart through up.sh restores the firewall
PASS  firewall active after restart via up.sh — marker present, example.com blocked

RESULT: all checks passed
```
