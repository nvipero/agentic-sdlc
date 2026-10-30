# Step 4 verification

Plan: [docs/plans/step-4.md](../plans/step-4.md), approved 2026-10-30. Filled in build step by build step (plan section 6).

## Build step 1: App and token (2026-10-30)

**Result:** the scripted exit check passes in full (all checks, none failed) against sdlc-pilot main with #41 (App token) and #43 (refresher fix) merged.

| Plan check | Evidence |
|---|---|
| `gh` and `git push` work from the container | `agent token can push a branch`, `can open a draft PR`; the zen check through the `gh` wrapper |
| A refreshed token is visible in the container at once | `a refreshed token is seen in the container at once — within 1 s`, then `gh and git work with the refreshed token` |
| The key is not in the container | `no private key anywhere the agent can read outside the project's dependencies — none`; the 1Password document is read only on the host |
| Neither the JWT nor a token in the host's process list | `no token, JWT, key or GH_TOKEN= in a host process list during mint, start and session — 56 samples` |
| An expired or missing token fails closed | `up.sh aborts when workspace init fails — init-workspace: no GitHub token at /etc/factory/token` |
| The App token cannot push a workflow file | `refusing to allow a GitHub App to create or update workflow` (draft 1 review finding N8: now verified, not only from community sources) |
| The App token cannot create a check run or commit status | both `HTTP 403 Resource not accessible by integration` |
| One repository, one hour | `the token reaches exactly one repository — nvipero/sdlc-pilot`; `token expires within an hour — 59 minutes left` |
| The agents have their own identity | the factory repo push is refused for `nvipero-factory-orchestrator[bot]` |

**Owner-run mint test before the container change:** the token is `ghs_`-prefixed, 390 bytes (longer than the 40 characters installation tokens used to have; nothing depends on the length), file mode 0600 in a 0700 directory, 60 minutes valid, one repository.

**Sleep test (owner, 2026-10-30):** the container stayed up while the Mac slept for more than the token's hour; after waking, `gh` in the container worked. The old fine-grained token (`sdlc-pilot-agents` on GitHub, `sdlc-pilot-github` in 1Password) is no longer read by anything and is revoked.

### Found and fixed while verifying

- **The refresher kept a caller waiting.** It inherited open pipe descriptors from `up.sh`'s caller, so the exit check's `reset-workspace` test, which reads `up.sh`'s output, waited until the refresher ended. Interactive use was not affected. The refresher now closes every descriptor above stderr (factory 577ae9b, sdlc-pilot #43); reproduced before the fix (4 s wait in a minimal case) and gone after it (0 s), and the full exit check then ran through.
- **`up.sh stop` said "stopped" when nothing ran.** It now says there was nothing to stop (sdlc-pilot #41).
- **Rancher Desktop's file sharing** (reverse-sshfs) shows the 0600 token file to the container's `node` user (uid 1000, file owner 501), keeps the mount read-only, and shows a file renamed into place within a second. Tested before relying on it.

### Exit check output (2026-10-30T14:51:17Z), step 4 section

```text
## Step 4: GitHub App token
PASS  the container's token is a GitHub App installation token (ghs_ prefix)
PASS  token expires within an hour — 59 minutes left
PASS  the token mount is read-only and holds only the token — read-only, entries: token
PASS  no private key anywhere the agent can read outside the project's dependencies — none
PASS  the token reaches exactly one repository — nvipero/sdlc-pilot
PASS  a refreshed token is seen in the container at once — within 1 s
PASS  gh and git work with the refreshed token — ed62ecd2119b
PASS  the host refresher runs — pid <pid>
PASS  App token cannot create a commit status — gh: Resource not accessible by integration (HTTP 403)
PASS  App token cannot create a check run — gh: Resource not accessible by integration (HTTP 403)

## Agent token reach (observed behaviour)
PASS  agent token can push a branch — pushed chore/exit-check-1793371889
PASS  agent token can open a draft PR — https://github.com/nvipero/sdlc-pilot/pull/44
PASS  agent token cannot push to main (ruleset, fast-forward commit) — remote: error: GH013: Repository rule violations found for refs/heads/main.
PASS  agent token cannot create a ruleset — gh: Resource not accessible by integration (HTTP 403)
PASS  agent token cannot change interaction limits — gh: Resource not accessible by integration (HTTP 403)
PASS  agent token cannot change repository settings — gh: Resource not accessible by integration (HTTP 403)
PASS  agent token cannot push a workflow file (no Workflows permission) —  ! [remote rejected] 609418d25340 -> chore/exit-check-workflow-1793371898 (refusing to allow a GitHub App to cre…
PASS  agent token cannot push to the factory repo — remote: Permission to nvipero/agentic-sdlc.git denied to nvipero-factory-orchestrator[bot].
PASS  probe branch and PR cleaned up (closed, not merged)

## Token never in a host process's arguments
PASS  no token, JWT, key or GH_TOKEN= in a host process list during mint, start and session — 56 samples

RESULT: all checks passed
```

The other sections (steps 1 to 3: overlays, network, restarts, plugin and roles, browser, protections, image rebuild, fail-closed start, workspace) passed unchanged; with the token now in a file, `credential-like env vars` reads `none` instead of `only GH_TOKEN`.
