---
description: Research and interview the owner, then write the project context and glossary on a branch for the owner's PR.
argument-hint: "[what to update, optional]"
disable-model-invocation: true
---

# /factory:context

You run the researcher's interview in this session. The owner is here and answers you directly.

## 1. Before you start

1. Work in `/workspace`. If `git status --porcelain` shows anything, stop and tell the owner what is uncommitted.
2. `git fetch -q origin main`.
3. Mode:
   - **New:** `origin/main` has no `docs/product-context.md` (`git cat-file -e origin/main:docs/product-context.md` fails). Branch `chore/project-context`.
   - **Update:** it exists. Branch `chore/update-project-context-<YYYYMMDD>` (today's date). The update covers what the owner wrote after the command: $ARGUMENTS. If that is empty, ask the owner what to update, in one question.
4. Branch:
   - If `origin/<branch>` exists and is **not** merged (`git merge-base --is-ancestor origin/<branch> origin/main` fails), check it out and continue from it: an earlier session was interrupted.
   - If it exists and **is** merged, it is a leftover: for an update, add `-2`, `-3` and so on to the name until it is free; for a new context there is nothing to do, because the context is already on `main` (switch to update mode).
   - Otherwise `git switch -c <branch> origin/main`.
5. **Model and language:** read `.factory/config.yaml`. Talk with the owner in `language.conversation` from the first line, and write the files in `language.repository`. If `roles.researcher.model` differs from this session's model, tell the owner in one line that the interview uses the session model, and that `/model <name>` switches it. Do not stop.

## 2. Interview

Load the `factory:researcher` skill with the Skill tool and follow it: research first, then the interview, then the two files, then the commit. The skill's rules apply in full, including the source tags.

## 3. Hand over

1. Check **every** commit on the branch before pushing: `git log --stat --format='%H%n%B' origin/main..HEAD`. Each commit touches only `docs/product-context.md` and `docs/glossary.md`; `git log --format='%h %(trailers:key=Factory-Role,valueonly,separator=)' origin/main..HEAD` shows `researcher` on every line; and `git status --porcelain` is empty. If not, stop and tell the owner what is wrong. Do not fix role files yourself.
2. `git push -u origin <branch>`.
3. Give the owner the link to open the PR: `https://github.com/<owner>/<repo>/compare/main...<branch>?expand=1`, with `<owner>/<repo>` from `gh repo view --json nameWithOwner --jq .nameWithOwner`.
4. Start the message with a TL;DR: what the context says, what stayed unconfirmed, and that it counts as approved once the owner merges the PR.

## Never

- Open, approve or merge a pull request.
- Write anything outside `docs/product-context.md` and `docs/glossary.md`.
- Touch issues or labels.
