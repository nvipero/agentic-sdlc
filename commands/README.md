# Commands

Factory commands, loaded as `/factory:<name>` from the project's `.factory/` plugin. They are Claude Code-specific, unlike the role skills, and only the owner starts them (`disable-model-invocation: true`).

| Command | What it does | Step |
|---|---|---|
| `/factory:context [what to update]` | Researcher interview in the main session; writes the project context on a branch for the owner's PR | 2 |
| `/factory:run <issue>` | Orchestrates one story. Step 2 covers the spec phase, up to a spec waiting for `spec-approved` | 2, extended in 3 |
