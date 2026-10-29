# Skills

One Agent Skill per factory role, in the [Agent Skills](https://agentskills.io/specification) format.
Roles: researcher, spec writer and spec reviewer (step 2); test writer, implementer and code reviewer (step 3).

Conventions, verified against agentskills.io/specification on 2026-10-21:

- One directory per skill, named like the skill: `skills/<name>/SKILL.md`.
- `name`: 1–64 characters, lowercase letters, digits and hyphens, no leading, trailing or double hyphens, equal to the directory name.
- `description`: 1–1024 characters, says what the skill does and when to use it.
- Optional standard fields only: `license`, `compatibility`, `metadata`, `allowed-tools`. Claude Code accepts extra fields, but other runtimes reject them, and roles must stay portable (spec principle 14). Model and tool choices belong in the role definition in `agents/`.
- Keep `SKILL.md` under 500 lines. Put details in `references/`, scripts in `scripts/`, and other files in `assets/`, one level deep.
