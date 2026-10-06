Ship the local changes: one commit, push, PR. The repo state at the end of this message was captured just now. Act on it, and don't re-check it.

1. If you're on the default branch (or detached), `git switch -c <type>/<slug>` first.
2. `git add -A -- ':/' ':(top,exclude,glob)**/.omo/**'`, then make ONE commit, `type(scope): description` in the style of the recent commits. Pass the message with `-m`, not a temp file.
3. `git push -u origin HEAD`.
4. If the branch has an open PR, the push updated it. Otherwise run `gh pr create --base <default>`. If the repo has its own PR instructions (for example `.agents/skills/open-pull-request`), follow them for the preflight, title and body. Otherwise write a 2-4 bullet body.
5. If the arguments say `merge`, finish with `gh pr merge --squash --delete-branch`.

Skip what the work already covered:
- Don't load the git-master skill.
- Don't re-run tests, builds, or type checks; the pre-commit hooks run on commit.
- Don't re-verify the commit with `git log` or `git show` afterwards.

Never force-push, rewrite pushed history, or use `--no-verify` on your own. If a hook fails on something this change didn't cause, or the push or merge is rejected or conflicts, stop and tell me.

End with the diffstat, the commit title, the PR URL, and the merge result if merged.
