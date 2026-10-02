# worktree pr part — `wtpr`: create (or switch to) a worktree from a GitHub PR.
# The only core command that shells out to `gh`. Same-repo PRs check out the
# PR's real head branch (so push/pull work naturally); fork PRs are fetched
# into a namespaced `pr-N` branch (no push access, avoids local name clashes).
#
# `wtprr` is a throwaway PR review sandbox: a detached git worktree in a temp
# dir holding the PR's code, with the PR context (branch, metadata, commits,
# changed files) appended to its AGENTS.md so opencode loads it into the system
# prompt automatically. By default the session opens with a seeded, advisory
# review brief — a summary plus a per-file pseudo-code skim of the changes in
# dependency order; pass --raw to skip it and just type your own questions. When
# opencode exits the worktree + temp dir are removed. Run with a PR number,
# inside a worktree (no arg → the branch's PR), or no arg for an fzf picker.
{
  home = {
    programs.fish.functions.wtprr = ''
      git rev-parse --show-toplevel >/dev/null 2>&1
      or begin; echo "wtprr: not a git repo"; return 1; end

      # --raw (anywhere): skip the seeded review brief, open a silent session.
      # Strip it out so the positional PR arg parsing below is unaffected.
      set -l raw 0
      if contains -- --raw $argv
        set raw 1
        set -e argv[(contains -i -- --raw $argv)]
      end

      set -l pr (string replace -r '^#' "" -- $argv[1])

      # No arg: prefer the current branch's PR, else fzf over open PRs (wtpr's picker).
      if test -z "$pr"
        set pr (gh pr view --json number --jq .number 2>/dev/null)
      end
      if test -z "$pr"
        set -l selection (gh pr list --limit 50 --json number,title,headRefName,author,isDraft --template '{{range .}}#{{.number}}  {{if .isDraft}}[DRAFT] {{end}}{{.title}}  ({{.headRefName}})  @{{.author.login}}{{"\n"}}{{end}}' 2>/dev/null | fzf --prompt="review PR> " --height=40%)
        or return 1
        set pr (string match -r '^#(\d+)' -- $selection)[2]
      end

      if test -z "$pr"; or string match -qr '[^0-9]' -- "$pr"
        echo "wtprr: invalid PR number"
        return 1
      end

      # Throwaway detached worktree at the PR head. refs/pull/N/head covers both
      # same-repo and fork PRs; it shares the repo's object db — no clone. The
      # worktree lives in a fresh, not-yet-existing subdir (worktree add needs
      # the path absent).
      set -l tmpbase (mktemp -d)
      set -l tmp "$tmpbase/pr-$pr"
      git fetch origin "pull/$pr/head" 2>/dev/null
      or begin; echo "wtprr: failed to fetch PR #$pr"; rm -rf "$tmpbase"; return 1; end
      git worktree add --detach "$tmp" FETCH_HEAD 2>/dev/null
      or begin; echo "wtprr: failed to create worktree"; rm -rf "$tmpbase"; return 1; end

      # Append the PR context to AGENTS.md so opencode loads it into the system
      # prompt on startup (append, not overwrite — keeps any existing AGENTS.md).
      begin
        echo
        echo "# PR review context (sandbox)"
        echo
        echo "This is a throwaway detached worktree checked out at the head of GitHub PR #$pr. The working tree holds the PR's code. Below are the PR's metadata, commits, and changed files. Help review it — answer questions about the implementation and how the code correlates with the changes. Don't push or open PRs."
        echo
        echo "## Metadata"
        gh pr view "$pr" 2>/dev/null
        echo
        echo "## Commits"
        gh pr view "$pr" --json commits --jq '.commits[] | "- \(.oid[0:9]) \(.messageHeadline)"' 2>/dev/null
        echo
        echo "## Changed files"
        gh pr diff "$pr" --name-only 2>/dev/null
      end >>"$tmp/AGENTS.md"

      # Open opencode on the sandbox. Default: seed an advisory review brief so
      # the session opens with a reading guide (tests + asserts, duplication,
      # where to look) instead of silence; it ends with a "verify these
      # yourself" list so it stays a guide, not a verdict. --raw skips it.
      if test $raw -eq 1
        opencode "$tmp"
      else
        set -l review_brief "Explain PR #$pr so I can skim it without reading the real code. Start with a one- or two-sentence summary of what it does and why. Then walk the changed files in dependency order (entry point first, then what it calls), and for each file give a short pseudo-code sketch of what its change does — plain, structural terms (new branches, calls, return changes, error handling, side effects), skipping cosmetic churn — so I can grasp the change without reading it line by line. Flag anywhere the ordering or a sketch is a guess. Call out anything notable or worth reading for real. Keep it concise and scannable; this is to help me decide what to read, not a substitute for reviewing — expand to the real code (\`gh pr diff $pr\` or the checked-out files) when a sketch looks off or matters."
        opencode --prompt "$review_brief" "$tmp"
      end

      # ponytail: cleanup is sequential (opencode runs in the foreground); no
      # trap, so a hard kill leaves the worktree — `git worktree prune` reaps it.
      git worktree remove --force "$tmp" 2>/dev/null
      rm -rf "$tmpbase"
      echo "wtprr: cleaned up review sandbox for PR #$pr"
    '';

    programs.fish.functions.wtpr = ''
      set git_root (git rev-parse --show-toplevel 2>/dev/null)
      or begin; echo "wtpr: not a git repo"; return 1; end

      _git_clean_stale_lock

      set pr_num $argv[1]
      set name $argv[2]

      # No PR number: fzf picker over open PRs
      if test -z "$pr_num"
        set -l selection (gh pr list --limit 50 --json number,title,headRefName,author,isDraft --template '{{range .}}#{{.number}}  {{if .isDraft}}[DRAFT] {{end}}{{.title}}  ({{.headRefName}})  @{{.author.login}}{{"\n"}}{{end}}' 2>/dev/null | fzf --prompt="PR> " --height=40%)
        or return 1
        set pr_num (string match -r '^#(\d+)' -- $selection)[2]
      end

      # Strip optional leading #
      set pr_num (string replace -r '^#' "" -- $pr_num)

      # Validate: non-empty and digits only
      if test -z "$pr_num"; or string match -qr '[^0-9]' -- "$pr_num"
        echo "wtpr: invalid PR number"
        return 1
      end

      # Resolve PR head branch + fork status in one call.
      # head_branch → default worktree name + branch checkout/tracking;
      # is_fork → branch-naming strategy in the creation block below.
      set pr_info (gh pr view $pr_num --json headRefName,isCrossRepository --jq '.headRefName, (.isCrossRepository | tostring)' 2>/dev/null)
      or begin; echo "wtpr: PR #$pr_num not found"; return 1; end
      set head_branch $pr_info[1]
      set is_fork $pr_info[2]

      # No explicit name: prompt for a short worktree name to avoid the
      # huge tmux session labels that long branch names produce. The
      # branch itself is unchanged — checkout/tracking below uses
      # $head_branch; only the worktree dir + session label differ.
      # Sanitized branch (our wt.prefix dropped, slashes → dashes) is the
      # default, so my own "fernando/fix-foo" opens as just "fix-foo".
      if test -z "$name"
        set -l default_name (_wt_name $head_branch)
        read -P "wtpr: worktree name [$default_name]: " name
        or return 1
        test -z "$name"; and set name $default_name
      end

      set main_root (git worktree list --porcelain | head -1 | string replace "worktree " "")
      set repo_name (basename $main_root)
      set wt_base (dirname $main_root)
      set wt_path "$wt_base/$repo_name.worktrees/$name"

      # Same-repo PR: the PR's actual head branch, tracking origin, so `git
      # push`/`git pull` work naturally and the local name matches GitHub.
      # Fork PR: no push access, and the fork's head branch name may collide
      # locally (e.g. a fork's `main`), so a namespaced pr-N branch under
      # wt.prefix, like every branch wt invents.
      set -l branch $head_branch
      test "$is_fork" = "false"; or set branch (_wt_prefix)"pr-$pr_num"

      # The fetch is the only part wt can't do: it never touches the network
      # on its critical path, and a PR branch is exactly what its refs/remotes
      # may not have yet. Skipped for a worktree that already exists, which wt
      # just switches to. Re-running wtpr on a fork PR refreshes pr-N; the +
      # handles force-pushes.
      if not test -e "$wt_path/.git"
        echo "wtpr: fetching PR #$pr_num…"
        if test "$is_fork" = "false"
          git fetch origin "+refs/heads/$head_branch:refs/remotes/origin/$head_branch" 2>/dev/null
          or begin; echo "wtpr: failed to fetch PR branch"; return 1; end
        else
          git fetch origin "+pull/$pr_num/head:refs/heads/$branch" 2>/dev/null
          or begin; echo "wtpr: failed to fetch PR"; return 1; end
        end
      end

      # Everything else is wt's: pool claim, the checkout inside the new
      # session, .setup in a detached window, and the pool refill afterwards.
      # With the branch now local (or in refs/remotes), wt's branch resolution
      # checks it out instead of forking a new one from HEAD.
      wt "$name" "$branch"
    '';
  };
}
