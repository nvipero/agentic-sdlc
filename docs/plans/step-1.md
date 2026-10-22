# Step 1 plan: Foundations

Status: revision 3, waiting for owner approval
Spec: `specs/factory-v1-spec.md` revision 5 (commit `1694e59`), section 10, step 1
Date: 2026-10-22

## TL;DR

- **What gets built:**
  - The factory repo gets a project template:
    - a dev container whose workspace is a clone of the project repo inside a Docker volume, not my host clone
    - factory definitions overlaid read-only from the host clone
    - a firewall that fails closed
    - `scripts/up.sh`, which runs a preflight that fails closed and passes the 1Password token into the container
  - `sdlc-pilot` is created from the template.
  - Both repos get a ruleset on `main`, a six-month interaction limit, and secret scanning with push protection.
  - `sdlc-pilot` also gets labels, an issue form and a label-filtered Projects board.
- **Clone-in-volume (your item 3): evaluated and adopted.** A throwaway test on this machine showed no blocker (section 3), and Git's sparse checkout keeps the overlaid paths out of `git status` and `git add -A`.
- **What the overlays do not fix:** an agent can still commit changes to factory paths using git plumbing. The step 4 CI guard catches that. Until then, the ruleset guarantees that every change reaches `main` **only through a PR**. It does **not** guarantee that a human merges that PR.
- **Known limitation until step 4:** with a single GitHub identity, the agent token can merge a PR, because merging needs only Contents: write. A managed-settings deny rule for merge commands is defence in depth only. Spec revision 5, step 4, introduces a separate agent identity and a required approving review from you to close this.
- **Exit check:** a scripted check plus a real headless agent session. It covers:
  - the network stays closed when the firewall fails
  - the agent token is rejected on a push to `main`
  - protections are read back through the API
  - a changed `.devcontainer/` produces a rebuilt image
  - the merge capability is recorded as a known limitation, verified from documentation and the token's permissions without merging anything
- **What I need from you:**
  - approval of this plan
  - approval before each GitHub change (section 1)
  - one OAuth login in the container
  - the board's auto-add rule in the UI
  - merging the factory PR

## Changes from revision 2

| # | Change | Your item |
|---|---|---|
| 1 | The claim "only through a PR you merge" is corrected to "only through a PR" (TL;DR, section 3). The agent token's ability to merge is a known limitation until step 4. A managed-settings deny rule covers merge commands (section 2), and an exit check item records the limitation without merging (section 7) | 1 |
| 2 | Firewall bootstrap: `api.github.com` is resolved into the ipset and allowed **before** the meta fetch, and it is added to `allowlist.txt` (section 5) | 2 |
| 3 | `waitFor: "postStartCommand"` in `devcontainer.json` (section 2) | 3 |
| 4 | `up.sh` always builds the image and proves the result matches the current `.devcontainer/` tree, through a hash label, before starting. An exit check item covers this (sections 4 and 7) | 4 |
| 5 | Evidence is redacted before committing: home paths, user name, host name, private IPs (section 7) | 5 |
| 6 | Idea view: `is:open -label:ready-for-factory`, with no type condition (section 6) | 6 |
| 7 | The three defaults in section 8 are now decisions | 7 |

**Spec alignment (revision 5, commit `1694e59`):**
- **Step 4** now adds a separate agent identity, so the ruleset can require your approving review. This plan treats merge capability as open until then.
- **Section 11** adds "No agent merged a pull request". Until step 4, the evidence is the `merged_by` field on merged PRs, which is always your account because the identity is shared. That makes the evidence weak, and the plan says so instead of claiming more.
- **Section 12** names the deny rule as the only backing in steps 1–3, which matches section 2 here.
- **Step 1 exit** includes "cannot push directly to `main`", which the exit check covers.

## Changes from revision 1

| # | Change | Your item |
|---|---|---|
| 1 | Ruleset, interaction limit and secret scanning with push protection on both repos, applied with `scripts/setup-github.sh` after approval per change | 1 |
| 2 | Fail-closed preflight in `up.sh`: ruleset, interaction limit (warns under 14 days), visibility, and a clean host clone fast-forwarded to `origin/main` | 2 |
| 3 | Workspace is a clone in a named volume, made with the agent token. Host `.git` and `scripts/up.sh` are not visible. The read-only `.git/hooks` and `.git/config` mounts are dropped, because they are no longer needed | 3 |
| 4 | Managed settings: connectors, non-essential traffic, updates and artifacts are all disabled. Exact names verified. `skipWebFetchPreflight` removed | 4 |
| 5 | Firewall sets DROP first and exits non-zero on any failure. `up.sh` aborts on a failed `devcontainer up` and probes the network before exec. New exit check item | 5 |
| 6 | Token through `remoteEnv` with a `docker inspect` check, falling back to `--remote-env` | 6 |
| 7 | Claude Code from Anthropic's signed apt repo, pinned, root-owned, never in home. Base image `node:24` pinned by digest | 7 |
| 8 | "Idea" board view | 8 |
| 9 | No VS Code attach and no VS Code hosts | 9 |
| 10 | Exit check: agent token push to `main` rejected, and protections verified through the API | 10 |
| 11 | Vault, token and clone are treated as existing, and dropped from the plan | 11 |
| 12 | Notes for step 2, section 11 | 12 |
| 13 | **New from evaluation:** `up.sh` always recreates the container. The volume persists, so no work is lost. This closes a pre-firewall window and stale overlays (section 4) | — |
| 14 | **New from evaluation:** the firewall and the workspace clone both run in `postStartCommand`, firewall first, because `postCreateCommand` runs before it with the network open | 5 |

## 1. What I create, and where

### Factory repo (`agentic-sdlc`), branch `feat/step-1-foundations`, merged through a PR you approve

```
README.md                          how to start a new project with the factory
skills/README.md                   Agent Skills conventions (verified format, section 9); no skills yet
agents/README.md                   placeholder (step 2)
commands/README.md                 placeholder (step 3)
scripts/setup-github.sh            idempotent, host-side, your gh login: protections, labels, board
scripts/exit-check.sh              runs the step 1 checks against a running container from the host
docs/plans/step-1.md               this plan
docs/verification/step-1.md        what was verified, where, and the exit check evidence
templates/project/
  .factory/config.yaml             config from spec section 4
  .factory/{skills,agents,commands}/.gitkeep
  .claude/settings.json            minimal; no limit relies on it
  .devcontainer/devcontainer.json
  .devcontainer/Dockerfile
  .devcontainer/init-firewall.sh   derived from Anthropic's reference, fail-closed (section 5)
  .devcontainer/init-workspace.sh  clones the repo into the volume if empty (section 3)
  .devcontainer/allowlist.txt
  .devcontainer/managed-settings.json
  .github/ISSUE_TEMPLATE/user-story.yml
  CLAUDE.md
  scripts/up.sh
  docs/ specs/ src/ tests/acceptance/ tests/unit/   (.gitkeep)
```

The token reference follows the convention `op://Agent Factory/<repo-name>-github/credential`, and `FACTORY_TOKEN_REF` overrides it. The template needs no edits per project.

### GitHub: each line is approved by you before I run it

| Order | Change | Repo | Credential |
|---|---|---|---|
| 1 | Push the initial commit to `main` | sdlc-pilot | your host git login |
| 2 | Ruleset on `main` (below) | sdlc-pilot | your gh login |
| 3 | Interaction limit `collaborators_only`, `six_months` | sdlc-pilot | your gh login |
| 4 | Secret scanning and push protection enabled | sdlc-pilot | your gh login |
| 5 | Ten labels | sdlc-pilot | your gh login |
| 6 | Projects board "sdlc-pilot", linked, with saved views | user nvipero | your gh login (already has the `project` scope) |
| 7 | Auto-add workflow on the board | — | **you, in the UI** (there is no API for it) |
| 8 | Push the branch and open the PR | agentic-sdlc | your gh login |
| 9 | Ruleset, interaction limit, secret scanning: same as 2–4 | agentic-sdlc | your gh login |

The order matters:
- Step 1 must happen before step 2. Once the ruleset blocks direct pushes, the initial commit can no longer go to `main`. The ruleset has no bypass actors, and that applies to you too.
- Step 8 happens before step 9 for the same reason, because the factory PR comes from a branch.

Ruleset body, built from the documented schema:

```json
{"name":"protect-main","target":"branch","enforcement":"active","bypass_actors":[],
 "conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},
 "rules":[{"type":"pull_request","parameters":{"required_approving_review_count":0,
   "dismiss_stale_reviews_on_push":false,"require_code_owner_review":false,
   "require_last_push_approval":false,"required_review_thread_resolution":false}},
  {"type":"non_fast_forward"},{"type":"deletion"}]}
```

## 2. Container

- **Base image:** `node:24-trixie-slim`, pinned by digest.
  - Node 24 has been Maintenance LTS since 2026-10-20, with end of life on 2028-04-30.
  - Node 26 becomes LTS only on 2026-10-28, and no line is in Active LTS between those dates.
  - I would move to 26 in step 4, when the stack is set up. Source: nodejs.org previous-releases page and `nodejs/Release` schedule.json.
- **User:** `node` (uid 1000), non-root. Claude Code refuses bypass mode as root.
- **Claude Code** is installed from Anthropic's signed apt repository at image build time:
  - Key: `https://downloads.claude.ai/keys/claude-code.asc`, with fingerprint `31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE` checked during the build.
  - Repo: `.../claude-code/apt/stable`.
  - Pinned: `claude-code=<version>` plus `apt-mark hold`. The latest version on 2026-10-22 is 2.1.308; I will pin the newest one the stable channel offers.
  - The binary is root-owned under `/usr`. `downloads.claude.ai` is reached only during the host-side build, so it is **not** on the runtime allowlist.
  - The exit check confirms there is no `claude` binary anywhere under `/home/node`.
- **No Docker socket and no host paths** except the read-only overlays.
- **Capabilities:** `capAdd: ["NET_ADMIN","NET_RAW"]`.
  - The only sudo rule is `node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh`.
  - The script takes no arguments, and sudo resets the environment.
- **Claude Code state:** a named volume per project at `/home/node/.claude`, with `CLAUDE_CONFIG_DIR` pointing to it.
- **`userEnvProbe: "none"`:** no login shell runs before the firewall is up.
- **`waitFor: "postStartCommand"`:** the CLI does not report the container as ready until the firewall and workspace init have finished.
- **Image identity:** the Dockerfile ends with `ARG DEVCONTAINER_TREE` and `LABEL factory.devcontainer.tree=$DEVCONTAINER_TREE`. `devcontainer.json` passes the build arg from `${localEnv:FACTORY_DEVCONTAINER_TREE}`. The label comes last so it does not break the layer cache (section 4).
- **No VS Code:** no extensions and no customizations. `up.sh` is the only supported way in.
- **Managed settings** (`/etc/claude-code/managed-settings.json`, root-owned, highest precedence; names verified in code.claude.com/docs settings and env-vars):

```json
{
  "disableClaudeAiConnectors": true,
  "enableArtifact": false,
  "permissions": {
    "deny": [
      "Bash(gh pr merge *)",
      "Bash(gh api *merge*)",
      "Bash(gh api *Merge*)"
    ]
  },
  "env": {
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "DISABLE_UPDATES": "1",
    "CLAUDE_CODE_DISABLE_ARTIFACT": "1",
    "CLAUDE_CONFIG_DIR": "/home/node/.claude"
  }
}
```

  Notes on these settings:
  - **Updates:** `DISABLE_UPDATES` blocks manual `claude update` and `claude install` as well, so `DISABLE_AUTOUPDATER` is redundant.
  - **Artifacts:** the setting and the env var are both used, belt and braces. Each documents that nothing can turn the tool back on.
  - **Side effects:** disabling non-essential traffic also turns off feature flags and Remote Control. That is acceptable.
  - **Limit:** managed `env` overrides the shell environment. The docs say Claude Desktop and self-hosted runners are an exception; neither applies here.
  - **Merge deny rules (defence in depth only):**
    - The rules cover `gh pr merge` (including `--auto`), the REST endpoint `PUT .../pulls/{n}/merge` through `gh api`, and the GraphQL mutations `mergePullRequest` and `enablePullRequestAutoMerge` through `gh api graphql`.
    - The `*merge*` rule also blocks harmless reads such as `gh api .../pulls/1/merge` (GET). That is acceptable.
    - The docs say plainly that a Bash rule "isn't a security boundary around the program". The rules do not stop `curl` with `$GH_TOKEN`, `sh -c '…'`, `/usr/bin/gh`, a GraphQL query read from a file, or a script.
    - Managed deny rules cannot be overridden by any other scope (code.claude.com/docs/en/permissions).
    - The docs do not say explicitly that deny rules still apply in bypass mode. They say bypass "skips permission prompts", and a deny rule is not a prompt. **The exit check tests this** with `gh pr merge --help`, which matches the rule and merges nothing.

## 3. Workspace: clone in a named volume

**Design:**
- **Workspace:** `workspaceMount` is a named volume `<project>-workspace` at `/workspace`. The Dockerfile creates `/workspace` owned by `node`, so the first mount copies that ownership into the empty volume.
- **Read-only overlays** are string-form `mounts` with `readonly`, sourced from the host clone:
  - `.factory/`, `.claude/`, `.github/`, `.devcontainer/` (directories)
  - `CLAUDE.md` (single file)
- **First clone:** `init-workspace.sh`, root-owned in the image, clones into the volume with the agent token when `/workspace/.git` is missing. It runs `git init`, sets `sparse.expectFilesOutsideOfPatterns=true` and these sparse patterns, then fetches and checks out `main`:
  - `/*`
  - `!/.factory/`, `!/.claude/`, `!/.github/`, `!/.devcontainer/`
  - `!/CLAUDE.md`, `!/scripts/up.sh`
- **What that gives:**
  - Git never writes to the read-only paths.
  - `git status` and `git add -A` ignore the overlays.
  - `scripts/up.sh` does not exist in the container at all.
- **Git auth inside:** `gh auth setup-git` with `GH_TOKEN`. The token is never put in a remote URL.

**Evaluation evidence** (throwaway containers on this Mac, 2026-10-22, all test material deleted afterwards):

| Check | Result |
|---|---|
| Read-only bind mounts layered over a named volume | Work. `findmnt`: `/workspace ext4 rw`, overlays `fuse.sshfs ro` |
| Writes to the overlays | `Read-only file system` |
| Writes elsewhere in the workspace | Work |
| Empty volume picks up `node` ownership from the image | `drwxr-xr-x node node /workspace` |
| `git init` + sparse patterns + `checkout main` with overlay mountpoints present | Works (git 2.47.3 in trixie) |
| Overlays visible to `git status` / `git add -A` with `sparse.expectFilesOutsideOfPatterns=true` | Not visible. Without that setting they show as ` M` |
| ipset + iptables inside a `NET_ADMIN` container | Works (`iptables v1.8.11 (nf_tables)`) |
| Rancher file sharing type | reverse-sshfs (`fuse.sshfs`), now used only for the small overlays |

**What this design removes**, as you listed: the `.git/hooks` and `.git/config` route to the host, agent commits reaching your host repo, tampering with `up.sh` through git, git breaking on a read-only config, and sshfs performance on the workspace.

**What remains:**
- **Factory paths via git plumbing.** An agent can still create commits that change factory paths, because the index and objects are writable. It can also disable sparse checkout or create a story worktree that has no overlays.
  - The ruleset guarantees these changes can reach `main` **only through a PR**. Until step 4, the agent token can also **merge** that PR itself, because merging needs only Contents: write and there is one GitHub identity.
  - The merge deny rules (section 2) only make that less likely by accident. They do not prevent it.
  - Step 4 closes this with the factory definitions guard as a required check, and a separate agent identity. With that identity, the ruleset can require your approving review (spec revision 5, section 10).
  - Until then, the exposure is short: agents open no PRs before step 3 (spec section 12). The PR history on GitHub is the audit trail, but `merged_by` cannot tell you from an agent while you share one identity.
- **The volume holds unpushed work.** Deleting it loses that work. `up.sh` never deletes it.

## 4. `scripts/up.sh`

Each step fails closed: any failure prints the reason and exits non-zero, and nothing later runs.

1. **Preflight (host, your gh login):**
   - `gh repo view --json visibility` returns `PUBLIC`.
   - **Ruleset:** `rules/branches/main` has active `pull_request`, `non_fast_forward` and `deletion` rules, and every active ruleset that applies to `main` has `bypass_actors == []`.
   - **Interaction limit:** `GET interaction-limits` returns `limit == collaborators_only` with `expires_at` in the future. It warns if fewer than 14 days are left. An empty response is a failure.
2. **Host clone:**
   - It is on `main` and has no local changes.
   - `git fetch` then `git merge --ff-only origin/main`.
   - The overlays therefore always equal `origin/main`.
3. **Token:** `op read "op://Agent Factory/<repo>-github/credential"` goes into a variable, exported as `FACTORY_GH_TOKEN` for this process only. It is never echoed and never written to disk.
4. **Image:**
   - `FACTORY_DEVCONTAINER_TREE="$(git rev-parse HEAD:.devcontainer)"`, the git tree hash of `.devcontainer/` on the fast-forwarded `main`.
   - Then `devcontainer build --workspace-folder <host clone>` on every run. Docker's layer cache makes an unchanged build take seconds, and any changed file in `.devcontainer/` (Dockerfile, managed settings, firewall, allowlist) invalidates the affected layers.
   - After `up`, the running container's image must carry `factory.devcontainer.tree` equal to that hash. If it doesn't, the container is stopped and `up.sh` aborts.
   - So a policy change on `main` always takes effect, or nothing starts.
   - The build step is a function, so the exit check can call it on its own.
5. **Container:** `devcontainer up --workspace-folder <host clone> --remove-existing-container`.
   - It is always recreated. That closes the gap between container start and firewall start for anything left in the old container layer, and it refreshes the overlays.
   - The volumes persist.
   - If `up` exits non-zero, `up.sh` aborts. Per CLI source, a failed `postStartCommand` makes `up` exit with 1.
6. **Network probe before exec:** from inside the container, `example.com` must fail and `api.github.com` must succeed. If either result is wrong, the container is stopped and `up.sh` aborts.
7. **Exec:** `devcontainer exec ... zsh`, or `up.sh exec <cmd>`.

**Token delivery:** `devcontainer.json` `"remoteEnv": {"GH_TOKEN": "${localEnv:FACTORY_GH_TOKEN}"}`. Per CLI source, `remoteEnv` reaches lifecycle commands and every exec.

The CLI writes the raw `remoteEnv` into the `devcontainer.metadata` label. Whether that copy holds `${localEnv:...}` or the resolved value is not clear from the source, so:
- I check `docker inspect` by comparing a hash of the token, printing only found or not found.
- If it is found, I switch to `--remote-env GH_TOKEN=...` on both `up` and `exec`. Per source, the CLI does not store that in the label.
- The cost of the fallback: the token is in the argv of a short-lived host process, visible to your own user's processes. I will report which option I used.

## 5. Firewall (fail closed)

`init-firewall.sh` runs from `postStartCommand` on every start, as `sudo init-firewall.sh && init-workspace.sh`. Nothing else runs in `onCreateCommand` or `postCreateCommand`, because those run before `postStartCommand` with the network open.

1. **First action:** `set -euo pipefail`, then `iptables -P INPUT DROP; -P OUTPUT DROP; -P FORWARD DROP`, before any flush or lookup.
2. **Rule rebuild:** flush, then allow loopback and established traffic. DNS is allowed only to the nameserver in `/etc/resolv.conf`.
3. **Bootstrap:** resolve `api.github.com` with `dig`, add its addresses to the ipset, and allow the set. Only then fetch `https://api.github.com/meta`, which would otherwise fail after `OUTPUT DROP`.
4. **Allowlist:**
   - Domains from `allowlist.txt` are resolved with `dig` into the same ipset.
   - GitHub `web`, `api` and `git` ranges are added from the meta document.
   - Any lookup failure, an empty answer, or a meta document failing its `jq` check: exit 1, and the policy stays DROP.
5. **Verification:** `example.com` and `1.1.1.1` are blocked, `api.github.com` is reachable. A wrong result exits 1.
6. **Success marker:** `/run/firewall-ok`, root-owned, written only after verification.

`allowlist.txt` contains:
- `api.github.com`, which is also bootstrapped before the meta fetch
- `api.anthropic.com`
- `claude.ai` and `platform.claude.com`, which OAuth login and refresh need per the current network docs
- `registry.npmjs.org`

Dropped from the reference: `statsig.com`, `sentry.io` (no longer in the docs), the VS Code hosts, outbound TCP 22, the host /24 accept, and DNS to any host.

The script reads an alternative allowlist path from an env var. Only real root can set it, because sudo resets the environment. The exit check uses this from the host (`docker exec -u root`) to force a failure.

Residual risks, not fixed in v1:
- **DNS tunnelling** through the allowed resolver.
- **Shared IPs:** CDN IPs can open other sites behind the same IPs.
- **All of GitHub is reachable.** The repo-scoped token limits writes.

## 6. Labels, issue form and board

- **Labels:** the ten from spec section 4, with colours and one-line descriptions.
- **`user-story.yml`:**
  - Fields: goal, user value, acceptance criteria, priority (dropdown).
  - Applies the `user-story` label automatically.
  - Blank issues stay enabled.
- **Board:** labels are the status. The saved views are:

| View | Filter |
|---|---|
| Idea | `is:open -label:ready-for-factory` |
| Ready for factory | `is:open label:ready-for-factory -label:spec-approved` |
| Needs human | `is:open label:needs-human` |
| Dispute | `is:open label:dispute` |
| In progress | `is:open label:spec-approved` |
| Done | `is:closed` |

The Idea view assumes `ready-for-factory` stays on an issue until it is closed. Otherwise, issues further along would fall back into Idea. That is a rule for the orchestrator in step 2.

The exact filter syntax for negation is checked when I create the views. If a filter is unsupported, I report it and adjust.

## 7. Exit check and evidence

The results are saved to `docs/verification/step-1.md` with command output. That file goes into a public repository, so:
- **No secrets:** nothing in the checks prints them.
- **Redaction before commit:** `exit-check.sh` writes raw output to the scratchpad only. A redaction filter then replaces:
  - the home directory path with `~`
  - the macOS user name with `<user>`
  - the host name with `<host>`
  - RFC 1918 and link-local addresses with `<private-ip>`, except Docker's well-known `172.17.0.1` and `127.0.0.11`
  - e-mail addresses with `<email>`
  - Rancher and Lima VM paths that contain any of the above
- **Manual review:** I then read the redacted file in full before committing it, and grep it for the original strings, which must have no hits. You see the file in the PR before it lands.

### A. Scripted (`scripts/exit-check.sh`, from the host)

- **Factory definitions:**
  - Writes to `.factory/`, `.claude/`, `.github/`, `.devcontainer/` and `CLAUDE.md` fail with `Read-only file system`.
  - `scripts/up.sh` does not exist in the container.
  - The host `.git` is not mounted.
  - `sudo -l` shows only the firewall script.
  - `iptables -F` as `node` fails.
  - There is no `claude` binary under `/home/node`.
- **Network:**
  - `example.com`, `google.com` and `1.1.1.1` are blocked.
  - `dig @8.8.8.8` is blocked.
  - The host gateway and `host.lima.internal` are blocked.
  - `api.anthropic.com`, `api.github.com` and `registry.npmjs.org` are reachable.
  - The rules are present again after a restart.
- **Network stays closed on firewall failure:** as root from the host, the firewall is re-run with an allowlist containing an unresolvable domain.
  - Expected: exit non-zero, and `api.github.com` is then also unreachable.
  - Separately, `up.sh` refuses to continue when `postStartCommand` fails, shown by running it against a container with a forced failure.
- **Visibility:**
  - `findmnt` shows only the workspace volume, the five read-only overlays and the Claude volume.
  - No `/Users`, no `docker.sock`, no `~/.ssh`.
  - Env variable names only: `GH_TOKEN` is the only credential-like one.
- **Token reach:**
  - `gh api user/repos` lists only `sdlc-pilot`.
  - The agent token gets 403 or 404 on the ruleset, interaction-limit and security-settings writes.
  - An empty commit pushed with `git push origin HEAD:main` is rejected with a ruleset violation. The preflight has already confirmed the ruleset, so a stray commit on `main` is not a realistic outcome.
- **Token on disk:** the `docker inspect` hash check from section 4.
- **Merge capability, a known limitation recorded rather than tested by merging:**
  - The token's permissions are read through the API with your login (fine-grained token metadata, or the response headers `x-accepted-github-permissions` on a harmless call). Expected: Contents, Issues and Pull requests write.
  - These are cited against the documentation, which says merging needs Contents: write ("Permissions required for fine-grained PATs").
  - Inside a real agent session, `gh pr merge --help` is denied by the managed rule, which proves the rule is active in bypass mode.
  - Recorded as: "agent token can merge PRs — open until step 4".
- **Image rebuild on a `.devcontainer/` change:**
  - `exit-check.sh` creates a throwaway local branch in a temporary worktree of the host clone, in the scratchpad, never pushed. On it, it commits a change to `.devcontainer/managed-settings.json` (an extra harmless deny rule), then calls `up.sh`'s build function on that worktree.
  - Expected:
    - a new image whose `factory.devcontainer.tree` label equals the new tree hash
    - the changed rule present in `/etc/claude-code/managed-settings.json` in that image
    - the up-step refuses to start a container whose image label does not match the current tree
  - The worktree, branch and test image are deleted afterwards.
- **Protections through the API** (your gh login), for both repos:
  - the active ruleset with `bypass_actors: []` and the three rules
  - `interaction-limits` = `collaborators_only` with its expiry
  - `security_and_analysis` with secret scanning and push protection enabled
  - visibility `public`
- **Preflight fails closed:** `up.sh` is run with a temporary override pointing the preflight at the wrong expected visibility, and it refuses to start. No GitHub setting is changed for this test.

### B. A real agent session

`claude -p --dangerously-skip-permissions` inside the container is asked to try to:
- edit `CLAUDE.md` and `.claude/settings.json`
- read `scripts/up.sh`
- reach `https://example.com`
- find any host file
- push to `main`
- run `gh pr merge --help`, which should be denied by the managed rule

It reports what happened, and the transcript is the second piece of evidence.

## 8. Decisions (accepted by owner on 2026-10-22)

1. **Decision: Claude Code login is interactive inside the container,** and is stored in the Claude volume.
2. **Decision: Node 24 now, Node 26 in step 4.**
3. **Decision: the ruleset does not restrict the merge method.**

## 9. Verification sources

These are from revision 1 and still hold. They will be written out in full in `docs/verification/step-1.md`:
- **devcontainer:** string-form read-only mounts, `localEnv`, `remoteEnv` vs `containerEnv`, `capAdd`, lifecycle order. Sources: containers.dev json_reference, the schema, and devcontainers/cli source.
- **Reference devcontainer and firewall:** anthropics/claude-code/.devcontainer and code.claude.com/docs/en/devcontainer.
- **Agent Skills:** agentskills.io/specification and code.claude.com/docs/en/skills.

New in revision 2:

| Claim | Result | Source |
|---|---|---|
| Rulesets on GitHub Free | Enforced in public repos | docs.github.com: About rulesets |
| Ruleset schema, `~DEFAULT_BRANCH`, `bypass_actors` | As in section 1. `bypass_actors` is returned only with write access, which is fine for your login | docs.github.com/en/rest/repos/rules |
| Ruleset binds admins when there are no bypass actors | Inferred, not stated outright. **The exit check tests it** with the agent token, and the ruleset itself shows no bypass | docs.github.com: Available rules for rulesets |
| Interaction limits | `collaborators_only`, `six_months`. An empty GET means none. Needs admin | docs.github.com/en/rest/interactions/repos |
| Secret scanning | Automatic on public repos. Push protection is off by default at repo level. `PATCH` `security_and_analysis` needs admin, and so does reading it | docs.github.com: About secret scanning, About push protection, REST repos |
| Agent token cannot change protections | Rulesets, interaction limits and repo `PATCH` all need Administration | docs.github.com: Permissions required for fine-grained PATs |
| Managed setting names | `disableClaudeAiConnectors`, `enableArtifact`, env `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_UPDATES`, `CLAUDE_CODE_DISABLE_ARTIFACT`. Managed `env` overrides the shell | code.claude.com/docs/en/settings, /settings-reference, /env-vars |
| Signed apt repo | Exists. Key fingerprint and URLs as in section 2. No auto-update | code.claude.com/docs/en/setup |
| `--remote-env` reaches lifecycle commands and is not stored in the label. Failed `postStartCommand` makes `up` exit 1 | Verified in CLI source (`injectHeadless.ts`, `imageMetadata.ts`, `devContainersSpecCLI.ts`) | github.com/devcontainers/cli |
| Volume copy-up from the image | Documented. Ownership was not in the docs, and is **verified by test** (section 3) | docs.docker.com: Volumes |
| Node LTS status | 24 Maintenance, 26 LTS on 2026-10-28 | nodejs.org, nodejs/Release schedule.json |

Still unknown, and tested during implementation:
- OAuth login works through the firewall.
- The token does not end up in `docker inspect`.
- The board's negative label filters.
- Managed deny rules are enforced in bypass mode.
- `devcontainer build` followed by `up` uses the freshly built image. The image-label check enforces this either way.
- A ruleset with no bypass actors blocks your own direct push. I will not test this with your login. The agent-token test covers the mechanism.

## 10. Where I need you, and what can go wrong

- **You:** approve this plan, each GitHub change in section 1, the OAuth login in the container, the board auto-add rule in the UI, and the factory PR merge.
- **I do on my own:** everything else, reporting results and deviations.
- **Most likely reasons this slips:**
  - **OAuth login inside the container.** The domains needed during the browser flow may differ from the documented list. Fallback: the `setup-token` route in section 8.
  - **Stale single-file `CLAUDE.md` overlay** over reverse-sshfs after the host clone fast-forwards. This is mitigated by always recreating the container.

## 11. Notes for step 2 (not solved now)

- **Discovery:** wiring `.factory/` skills, agents and commands into Claude Code discovery. `--plugin-dir`, the `CLAUDE_CODE_PLUGIN_DIRS` env var and symlinks are the candidates, all verified to exist.
  - Story worktrees do not get the overlays, because they are sparse-excluded and have no mount. Sessions therefore have to run from `/workspace`, or discovery has to point at absolute overlay paths.
- **Trusted input:** the orchestrator trusts only issue and comment content authored by you, as defence in depth on top of the interaction limit.
