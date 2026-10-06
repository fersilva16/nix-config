---
description: Commit all local changes as one conventional commit, push, and open a PR (`merge` also squash-merges it)
argument-hint: "[merge]"
disable-model-invocation: true
allowed-tools:
  - Bash(git status *)
  - Bash(git diff *)
  - Bash(git log *)
  - Bash(git show *)
  - Bash(git branch *)
  - Bash(git switch *)
  - Bash(git fetch *)
  - Bash(git add *)
  - Bash(git commit *)
  - Bash(git push *)
  - Bash(gh repo view *)
  - Bash(gh pr status *)
  - Bash(gh pr view *)
  - Bash(gh pr create *)
  - Bash(gh pr merge *)
---

Ship the local changes in this repo. Arguments (may be empty): $ARGUMENTS

## Current state

- Branch (empty = detached HEAD): !`git branch --show-current`
- Default branch: !`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`
- PR for this branch: !`gh pr status --json number,url,state,baseRefName,title --jq '.currentBranch // "none"'`
- Recent commits (match their style): !`git log --oneline -8`

Status:
!`git status --short --branch`

Diffstat vs HEAD (untracked files appear only in the status above):
!`git diff --stat HEAD`

## Steps

The state above is current: do not re-run those commands. Read individual files or `git diff -- <path>` only when you need them to write the message.

1. **Nothing to ship**: if the status shows no changes and the branch is not ahead of its upstream, say so and stop.
2. **Branch**:
   - If on the default branch or detached, create a short descriptive branch: `git switch -c <type>/<slug>`.
   - If the branch's PR is `MERGED` or `CLOSED`, start a fresh branch from the default branch, carrying the changes: `git fetch origin <default>`, then `git switch -c <type>/<slug> origin/<default>`. If git refuses, stop and report.
   - Otherwise, stay on the current branch.
3. **Commit**: `git add -A`, then make ONE commit of everything. Leave existing commits alone.
   - Title: `type(scope): description`, imperative and lowercase, under 72 chars. The scope is the module/app/package that changed. Follow the repo's CLAUDE.md/AGENTS.md commit conventions if present.
   - Add a short body only when the title can't carry the why.
   - Pass the message with single-quoted `-m` args. Do not use a heredoc or `$(...)`.
   - If a file looks like a secret (`.env`, keys, tokens), stop before committing and report it.
   - If a pre-commit hook fails, fix what it reports (or re-stage what it reformatted) and commit again. Never use `--no-verify`.
4. **Push**: `git push -u origin HEAD`.
5. **PR**:
   - If an `OPEN` PR exists for the branch, the push updated it. Do not create another.
   - Otherwise run `gh pr create --base <default> --title '<commit title>' --body '<body>'`. The body is 2-4 short bullets on what changed and why, single-quoted.
6. **Merge** (only if the arguments contain `merge`): `gh pr merge --squash --delete-branch`.
   - If gh refuses (checks pending, conflicts, protection), report why and stop. Never use `--admin`.
   - If the merge succeeded but the local branch cleanup failed (common in git worktrees), say so and leave it.

## Hard rules

- Never force-push (`--force`, `--force-with-lease`, `+refspec`). Never rewrite history that is already pushed (no rebase, amend, or reset of pushed commits).
- If the push is rejected or anything conflicts, stop and report it. Do not pull, rebase, or merge to resolve it.
- Never post PR comments or reviews. The PR body is the only text you write on GitHub.

## Final message

Keep it short:

1. The diffstat of the commit (`git show --stat --format= HEAD`) in a code block
2. The commit title
3. The PR URL, noting whether it is new or updated
4. The merge result, if merged
