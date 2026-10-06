---
description: Commit all local changes as one commit, push, and open a PR (merge also squash-merges it)
argument-hint: "[merge]"
---
Commit all local changes (except `.omo/`) as one conventional commit, push, and open a PR against the repo's default branch. If the branch already has an open PR, just push to it. If you're on the default branch, create a branch first.

If the arguments say `merge`, finish with `gh pr merge --squash --delete-branch`. Arguments: $ARGUMENTS

Never force-push or rewrite pushed history. If the push is rejected or anything conflicts, stop and tell me. End with the diffstat, the commit title, and the PR URL (plus the merge result, if merged).
