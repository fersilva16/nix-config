# worktree pr part — `wtpr`: create (or switch to) a worktree from a GitHub PR.
# The only core command that shells out to `gh`. Same-repo PRs check out the
# PR's real head branch (so push/pull work naturally); fork PRs are fetched
# into a namespaced `pr-N` branch (no push access, avoids local name clashes).
#
# `wtprr` is a throwaway PR review sandbox: a detached git worktree in a temp
# dir holding the PR's code, with the PR context (branch, metadata, commits,
# changed files) appended to its AGENTS.md so opencode loads it into the system
# prompt automatically — no seed prompt, you just type your questions. When
# opencode exits the worktree + temp dir are removed. Run with a PR number,
# inside a worktree (no arg → the branch's PR), or no arg for an fzf picker.
{
  home = {
    programs.fish.functions.wtprr = ''
      git rev-parse --show-toplevel >/dev/null 2>&1
      or begin; echo "wtprr: not a git repo"; return 1; end

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

      # Open opencode on the sandbox — no seed prompt; you ask the questions.
      opencode "$tmp"

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
      # Sanitized branch (slashes → dashes) is offered as the default.
      if test -z "$name"
        set -l default_name (string replace -a '/' '-' -- $head_branch)
        read -P "wtpr: worktree name [$default_name]: " name
        or return 1
        test -z "$name"; and set name $default_name
      end

      set main_root (git worktree list --porcelain | head -1 | string replace "worktree " "")
      set repo_name (basename $main_root)
      set wt_base (dirname $main_root)
      set wt_path "$wt_base/$repo_name.worktrees/$name"

      # tmux: switch to existing session if it exists
      if set -q TMUX
        set parent_session (command tmux display-message -p '#{session_name}' | string split -m 1 '/')[1]
        set session_name "$parent_session/$name"

        if command tmux has-session -t "=$session_name" 2>/dev/null
          command tmux switch-client -t "=$session_name"
          return 0
        end
      end

      # Create worktree if missing
      set -l is_new 0
      if not test -d "$wt_path"
        if test "$is_fork" = "false"
          # Same-repo PR: check out the PR's actual head branch tracking
          # origin, so `git push`/`git pull` work naturally and the local
          # branch name matches GitHub. Using pr-N here breaks push
          # (local/upstream names differ) and confuses tooling/LLMs.
          git fetch origin "+refs/heads/$head_branch:refs/remotes/origin/$head_branch" 2>/dev/null
          or begin; echo "wtpr: failed to fetch PR branch"; return 1; end

          if git show-ref --verify --quiet "refs/heads/$head_branch"
            # Local branch already exists: attach the worktree to it.
            git worktree add "$wt_path" "$head_branch"
          else
            # Create local branch tracking origin (mirrors wt's pattern).
            git worktree add --track -b "$head_branch" "$wt_path" "origin/$head_branch"
          end
          or begin; echo "wtpr: failed to create worktree"; return 1; end
        else
          # Fork PR: no push access, and the fork's head branch name may
          # collide locally (e.g. a fork's `main`). Fetch pull/N/head into
          # a namespaced pr-N branch; re-running wtpr refreshes force-pushed
          # PRs. The + forces fast-forward to handle force-pushes.
          set -l local_branch "pr-$pr_num"
          git fetch origin "+pull/$pr_num/head:refs/heads/$local_branch" 2>/dev/null
          or begin; echo "wtpr: failed to fetch PR"; return 1; end

          git worktree add "$wt_path" "$local_branch"
          or begin; echo "wtpr: failed to create worktree"; return 1; end
        end

        echo "Created worktree at $wt_path (PR #$pr_num: $head_branch)"
        direnv allow "$wt_path" 2>/dev/null
        set is_new 1
      end

      # Create tmux session and switch
      if set -q TMUX
        command tmux new-session -d -s "$session_name" -c "$wt_path"

        if test $is_new -eq 1
          set -l setup_file "$wt_base/$repo_name.worktrees/.setup"
          if test -f "$setup_file"
            command tmux send-keys -t "=$session_name" "sh '$setup_file'" Enter
          end
        end

        command tmux switch-client -t "=$session_name"
      else
        echo "Not in tmux — run: cd $wt_path && opencode"
      end
    '';
  };
}
