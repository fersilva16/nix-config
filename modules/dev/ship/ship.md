---
description: Commit all local changes as one conventional commit, push, and open a PR (merge also squash-merges it)
argument-hint: "[merge]"
---
Ship the local changes in this repo: commit them as one conventional commit, push, and open a PR. If the arguments contain `merge`, also squash-merge the PR.

Arguments: $ARGUMENTS

## 1. Discover (one batch)

Run this as a single shell command. Do not spend other tool calls on discovery. Read individual files or `git diff -- <path>` only when you need them to write the message.

```sh
cd "$(git rev-parse --show-toplevel)" &&
echo '== branch' && git branch --show-current &&
echo '== default branch' && gh repo view --json defaultBranchRef --jq .defaultBranchRef.name &&
echo '== PR for this branch' && gh pr status --json number,url,state,baseRefName,title --jq '.currentBranch // "none"' &&
echo '== recent commits' && git log --oneline -8 &&
echo '== status' && git status --short --branch -- . ':(exclude,glob)**/.omo/**' &&
echo '== diffstat' && git diff --stat HEAD
```

- If it fails (not a git repo, no GitHub remote, gh not authenticated), report the failing step and stop.
- An empty branch means detached HEAD.
- `.omo/` dirs are omo's own state and are never shipped.
- Run every later command from the repo root.

If the status shows no changes and the branch is not ahead of its upstream, say there is nothing to ship and stop.

## 2. Branch

- If on the default branch or detached, create a short descriptive branch: `git switch -c <type>/<slug>`.
- If the branch's PR is `MERGED` or `CLOSED`, start a fresh branch from the default branch, carrying the changes: `git fetch origin <default>`, then `git switch -c <type>/<slug> origin/<default>`. If git refuses, stop and report.
- Otherwise, stay on the current branch.

## 3. Commit

Stage everything except omo state with `git add -A -- ':/' ':(top,exclude,glob)**/.omo/**'`, then make ONE commit of it. Leave existing commits alone. If there are no local changes and the branch is only ahead of its upstream, skip the commit.

- Title: `type(scope): description`, imperative and lowercase, under 72 chars. The scope is the module/app/package that changed; match the recent commits and the repo's AGENTS.md/CLAUDE.md conventions.
- Add a short body only when the title can't carry the why.
- If a file looks like a secret (`.env`, keys, tokens), stop before committing and report it.
- If a pre-commit hook fails, fix what it reports (or re-stage what it reformatted) and commit again. Never use `--no-verify`.

## 4. Push

`git push -u origin HEAD`.

## 5. PR

- If an `OPEN` PR exists for the branch, the push updated it. Do not create another.
- Otherwise run `gh pr create --base <default> --title '<commit title>' --body-file <file>`. The body is 2-4 short bullets on what changed and why.

## 6. Merge (only if the arguments contain `merge`)

Run `gh pr merge --squash --delete-branch`.

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
