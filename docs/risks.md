# Known risks and accepted limitations

Accepted unless a backlog issue is linked. A security review does not report these as findings.

## Project risks

- **Building the factory becomes the project.** Mitigation: changes start from the [backlog](https://github.com/users/nvipero/projects/2), and real projects decide what is worth building.
- **Subscription limits.** Agent runs share the Team plan quota with the owner's other work ([#26](https://github.com/nvipero/agentic-sdlc/issues/26)).
- **Agent loops.** Mitigation: turn limits and dispute rules.
- **Specs approved without reading.** Mitigation: questions, choices and assumptions are surfaced separately ([#22](https://github.com/nvipero/agentic-sdlc/issues/22)).
- **Copied templates drift** from the factory as it evolves ([#39](https://github.com/nvipero/agentic-sdlc/issues/39)).
- **Interaction limit expires** after six months. Mitigation: `up.sh` checks it on every run.

## Security limitations

- **After the owner approves, the App could technically merge.** Only the deny rule in managed settings prevents it; the owner's approval is the decision that matters. Until 2026-10-30 ([history](history.md)) the agents acted as the owner and could merge without approval; agent commits from then carry the noreply address of an unrelated GitHub account (`factory-agent`) as author and are not rewritten.
- **Roles share the App.** Only commit trailers and the guards tell the roles apart; separate identities per role need separate sandboxes ([#49](https://github.com/nvipero/agentic-sdlc/issues/49), [#48](https://github.com/nvipero/agentic-sdlc/issues/48)).
- **Instruction files in role paths.** The guards protect only the root `CLAUDE.md` ([#20](https://github.com/nvipero/agentic-sdlc/issues/20)).
- **The mount table shows the host path.** `findmnt` inside the container shows the read-only overlays' source as the host path of the project clone, which includes the macOS user name. No host file outside the overlaid paths is readable. This is metadata, not access.
- **The workspace clone's `main` is not updated automatically.** The overlays follow the host clone's `main`, which the owner pulls, but the clone in the volume keeps the `main` it was created with. Agents fetch before branching. After a checkout between commits that differ in factory paths, git warns that it cannot unlink files in the read-only overlays; this is harmless, and `git status` stays clean.
- **Residual network risks:**
  - DNS tunnelling through the allowed resolver.
  - Shared CDN IPs behind allowlisted names.
  - **Allowlisted names are resolved only at firewall start.** If a CDN rotates its addresses during a session (for example npm, or Anthropic's API), connections to the new addresses are rejected until the next `up.sh` run. This is inherited from the reference script.
  - All of GitHub is reachable. The repo-scoped token limits writes.
  - Rejected connections are counted, not logged ([#29](https://github.com/nvipero/agentic-sdlc/issues/29)).
- **Migration check is a heuristic.** `migration-check.sh` matches destructive and authorisation-weakening statements in the SQL text, so SQL built at run time (`execute format(...)` in a `do` block or a function) is not seen, and a comment that names a `drop` costs a label; the code reviewer's database checklist is the second line.
- **Cloudflare target (frontend `host: cloudflare`):**
  - Workers Previews are an open beta in Wrangler.
  - A deleted Preview has been seen serving for hours on a static-assets Worker ([cloudflare/developer-platform#73](https://github.com/cloudflare/developer-platform/issues/73)). `preview-cleanup` warns when it happens; Access keeps it from the public meanwhile.
  - Every production version also has its own public address, `<version>-<repo>.<subdomain>.workers.dev` (not indexed): Workers Previews need the same setting. Production is public anyway; an old version stays reachable after a rollback or a new deploy.
  - `workers.dev` is a public suffix, so `<subdomain>.workers.dev` is one site: Previews and production of the same account share cookies set on that domain. On Vercel each project is its own site. A production custom domain would separate them.
- **One unauthenticated GitHub API call per container start.** The firewall fetches `https://api.github.com/meta` before the token exists in the container. GitHub allows 60 unauthenticated API requests per hour per IP. Dozens of starts within an hour, or other unauthenticated GitHub traffic from the same IP, can use that up. The firewall then fails, and the network stays closed until the limit resets.
