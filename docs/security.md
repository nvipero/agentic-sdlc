# Security

How the limits on agents are enforced: GitHub protections, the agents' identity and credentials, and the checks before every start. Accepted risks are in [risks](risks.md).

## Repository visibility and protections

Both the factory and project repositories are public. On a free GitHub account, rulesets and branch protection are enforced only in public repositories, and principle 5 requires enforced limits. The factory definitions would be public anyway, because the project template copies them into every project repo. A private project needs a paid plan ([#28](https://github.com/nvipero/agentic-sdlc/issues/28)).

Applied to the factory and every project:

- **Ruleset on `main`:** pull request required, force pushes and deletion blocked.
  - **Project repositories:** one approval, **review from code owners required** (`.github/CODEOWNERS` names only the owner), approvals dismissed by a new push, the gate checks required with GitHub Actions as their source, and CodeQL alerts of high severity blocking. One bypass actor: the admin role, in pull request mode, so the owner's own PRs (factory updates) merge without a second reviewer but never by direct push. The agents' App is not an admin and cannot bypass.
  - **The factory repository:** no required approvals (single maintainer), no checks (it runs no workflows), no bypass actors.
- **A merged branch is deleted automatically.**
- **Interaction limit "repository collaborators only":** outsiders cannot open issues or PRs, comment, react or edit. This keeps outside text out of agent input. The limit expires after at most six months.
- **Secret scanning and push protection** enabled.
- **GitHub Actions (projects):** only GitHub-owned actions, pinned to a full commit SHA; a read-only `GITHUB_TOKEN` that cannot approve or create pull requests; approval required for every outside contributor's run; no repository-level secrets (the deployment target's secrets, such as the Vercel or Cloudflare token, are in the `preview` and `production` environments, deployable from `main` only, and only the steps that call the target script get them); `pull_request_target` allowed by an Actions policy for `guards.yml` only, ahead of GitHub's default block on public repositories. The agents' App has no Workflows permission, so agents cannot change what runs. The dependency graph (needed by dependency review, turned on by hand) and CodeQL default setup are on. The factory repository keeps Actions disabled.

## Preflight in `up.sh`

`scripts/up.sh` verifies on the host, before starting the container, that the repository visibility is as expected, every ruleset is active and the project ruleset is as above, the interaction limit is active, secret scanning and push protection are on, and the Actions settings, policy, dependency graph and CodeQL are as above. If any check fails, it refuses to start agents. Protections that can lapse silently (expiring limits, plan changes) are checked on every run instead of trusted.

**The host clone is never updated automatically.** `up.sh` checks that the host clone is clean, on `main` and equal to `origin/main`, and refuses to start if it is behind. A merged change, including one to the read-only paths, therefore reaches the container only through the owner's own review and pull: `git log -p HEAD..origin/main`, then `git pull --ff-only`.

## Agent identity and credentials

- **The agents' GitHub identity is a GitHub App** (`nvipero-factory-orchestrator`), registered under the owner's account and installed only on project repositories, with Contents, Issues and Pull requests read and write and Metadata read. No Workflows, Administration, Checks or Commit statuses permission. The agents cannot act as the owner: merging a PR needs only Contents write, which the agent token must have, and nobody can approve their own PR, so a required approval from the owner needs a separate identity. A machine user was rejected: it cannot be limited below collaborator rights, needs a classic token for a repository it does not own, and uses up the one free machine account. Everything the factory writes on GitHub appears as the App; the owner's approval is the only one the ruleset accepts.
- **One-hour tokens minted on the host.** The App's private key is a document in the 1Password vault "Agent Factory" and never enters the container. `scripts/up.sh` reads it once per start (one confirmation), signs a JWT with `openssl`, and mints an installation token narrowed to the one repository and those permissions. A refresher started by `up.sh` keeps the key in memory and mints a new token when the current one is 45 minutes old or expires within 15, checking every minute, so a Mac waking from sleep gets a fresh token within a minute. It ends with the container or `up.sh stop`, which removes the token.
- **Delivery:** the token is written to a temporary file and renamed into a host directory outside the clone (`~/.factory-run/<project>/token/`, mode 0700), which is mounted read-only at `/etc/factory/token`. A directory, not the file, is mounted, because a single-file mount keeps the old file after a rename. In the image, a root-owned `gh` wrapper reads the token on every call and puts it only in the real `gh`'s environment; git uses the wrapper as its credential helper for github.com. No credential is in the container's environment or in any process's arguments on the host (key and JWT go through file descriptors and stdin). No long-lived credential is in the container.
- **The 1Password CLI is never installed in the container.** Access to the vault would expose all other credentials.
- No other credentials are placed in the container. Claude Code's own credentials are the only exception and are treated as exposed if the container is compromised.
- Anything given to the container can be read by agents. Protection comes from limiting the scope and lifetime of credentials, not from hiding them.
- **Commits** carry the App's bot address (`<id>+<app>[bot]@users.noreply.github.com`) and the role's name as author (`factory <role>`). Neither is authenticated; the `Factory-Role` trailer and the guards are what the checks rely on.

## Trusted input and owner-only labels

- **Owner-only labels** (`spec-approved`, `tests-change-approved`, `migration-approved`) count only when the issue's newest `labeled` event for them has the owner's account as actor; GitHub permissions are not per label. The orchestrator and the guards check this, and the `label-audit` workflow removes such a label added by anyone else and fails on label definition changes by anyone but the owner ("trust, but verify").
- **Trusted input** to the agents is text written by the owner that nobody else edited last (GraphQL `author` and `editor`), because the App can edit other accounts' text.
