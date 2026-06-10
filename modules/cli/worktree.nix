{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
mkUserModule {
  name = "worktree";
  requires = [
    "git"
    "fish"
  ];
  home =
    { userCfg, ... }:
    {
      # jq: used by wts land / _wts_pick_session to read av.db metadata.
      home.packages = lib.mkIf userCfg.av.enable [ pkgs.jq ];

      programs.fish = {
        functions = {
          wt = ''
            set git_root (git rev-parse --show-toplevel 2>/dev/null)
            or begin; echo "wt: not a git repo"; return 1; end

            _git_clean_stale_lock

            set name $argv[1]
            set branch $argv[2]

            set main_root (git worktree list --porcelain | head -1 | string replace "worktree " "")
            set repo_name (basename $main_root)
            set wt_base (dirname $main_root)

            # No args: fzf to switch to existing worktree
            if test -z "$name"
              if not set -q TMUX
                echo "wt: not in tmux"
                return 1
              end

              set wt_dir "$wt_base/$repo_name.worktrees"
              if not test -d "$wt_dir"; or test (count (command ls "$wt_dir" 2>/dev/null)) -eq 0
                echo "wt: no worktrees found"
                return 1
              end

              set name (command ls "$wt_dir" | fzf --prompt="worktree> " --height=40%)
              or return 1
            end

            set wt_path "$wt_base/$repo_name.worktrees/$name"

            if set -q TMUX
              # Use root session name (strip /suffix if called from a worktree session)
              set parent_session (command tmux display-message -p '#{session_name}' | string split -m 1 '/')[1]
              set session_name "$parent_session/$name"

              # Session already exists: just switch
              if command tmux has-session -t "=$session_name" 2>/dev/null
                command tmux switch-client -t "=$session_name"
                return 0
              end
            end

            # Create worktree if dir doesn't exist
            set -l is_new 0
            if not test -d "$wt_path"
              git fetch origin 2>/dev/null
              set base_branch (git rev-parse --abbrev-ref HEAD 2>/dev/null)
              if test -z "$base_branch" -o "$base_branch" = "HEAD"
                echo "wt: detached HEAD — checkout a branch first"
                return 1
              end

              if test -n "$branch"
                # Use existing branch, or create new branch from current
                if git show-ref --verify --quiet "refs/heads/$branch"
                  git worktree add "$wt_path" "$branch"
                else if git show-ref --verify --quiet "refs/remotes/origin/$branch"
                  git worktree add --track -b "$branch" "$wt_path" "origin/$branch"
                else
                  git worktree add -b "$branch" "$wt_path" "$base_branch"
                end
              else
                # New branch (named after worktree) from current branch
                git worktree add -b "$name" "$wt_path" "$base_branch"
              end
              or begin; echo "wt: failed to create worktree"; return 1; end
              echo "Created worktree at $wt_path (from $base_branch)"
              direnv allow "$wt_path" 2>/dev/null
              set is_new 1
            end

            # Create tmux session and switch
            if set -q TMUX
              command tmux new-session -d -s "$session_name" -c "$wt_path"

              # Run setup script for new worktrees
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

          wtmv = ''
            set git_root (git rev-parse --show-toplevel 2>/dev/null)
            or begin; echo "wtmv: not a git repo"; return 1; end

            _git_clean_stale_lock

            set main_root (git worktree list --porcelain | head -1 | string replace "worktree " "")
            set repo_name (basename $main_root)
            set wt_base (dirname $main_root)
            set wt_dir "$wt_base/$repo_name.worktrees"

            set old $argv[1]
            set new $argv[2]

            # One arg in a worktree session: rename current worktree to that name
            if test -z "$new"; and set -q TMUX
              set -l current (command tmux display-message -p '#{session_name}')
              if string match -q '*/*' -- "$current"
                set new $old
                set old (string split -m 1 '/' -- "$current")[2]
              end
            end

            # No old name: fzf picker
            if test -z "$old"
              if not test -d "$wt_dir"; or test (count (command ls "$wt_dir" 2>/dev/null)) -eq 0
                echo "wtmv: no worktrees found"
                return 1
              end
              set old (command ls "$wt_dir" | fzf --prompt="rename> " --height=40%)
              or return 1
            end

            # No new name: prompt for it
            if test -z "$new"
              read -P "wtmv: rename '$old' to: " new
              or return 1
            end

            if test -z "$new"
              echo "wtmv: new name required"
              return 1
            end

            if test "$old" = "$new"
              echo "wtmv: names are identical"
              return 1
            end

            set old_path "$wt_dir/$old"
            set new_path "$wt_dir/$new"

            if not test -d "$old_path"
              echo "wtmv: no worktree found for '$old'"
              return 1
            end
            if test -e "$new_path"
              echo "wtmv: '$new' already exists"
              return 1
            end

            # Capture branch before moving (to optionally rename it)
            set -l branch (git -C "$old_path" rev-parse --abbrev-ref HEAD 2>/dev/null)

            # Move the worktree — git updates its metadata + gitdir links.
            # Run from main_root so we're not inside the dir being moved.
            git -C "$main_root" worktree move "$old_path" "$new_path"
            or begin; echo "wtmv: failed to move worktree"; return 1; end

            # Rename the branch only when it matches the old worktree name
            # (the auto-named case from wt), fixing the typo everywhere.
            if test "$branch" = "$old"
              git -C "$main_root" branch -m "$old" "$new" 2>/dev/null
              and set branch "$new"
            end

            direnv allow "$new_path" 2>/dev/null

            # Rename the tmux session (parent/old -> parent/new)
            if set -q TMUX
              set -l old_session (command tmux list-sessions -F '#{session_name}' | grep "/$old\$" | head -1)
              if test -n "$old_session"
                set -l parent (string split -m 1 '/' -- "$old_session")[1]
                command tmux rename-session -t "=$old_session" "$parent/$new"
              end
            end

            echo "Renamed worktree '$old' → '$new'"
          '';

          wtls = "git worktree list $argv";

          wtpr = ''
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

            # Default worktree name = sanitized branch (slashes become dashes)
            if test -z "$name"
              set name (string replace -a '/' '-' -- $head_branch)
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

          wtrm = ''
            set git_root (git rev-parse --show-toplevel 2>/dev/null)
            or begin; echo "wtrm: not a git repo"; return 1; end

            set -l force 0
            set -l args
            for arg in $argv
              if test "$arg" = "--force" -o "$arg" = "-f"
                set force 1
              else
                set -a args $arg
              end
            end

            set name $args[1]

            set main_root (git worktree list --porcelain | head -1 | string replace "worktree " "")
            set repo_name (basename $main_root)
            set wt_base (dirname $main_root)

            # No arg: self-remove if in a worktree session, otherwise fzf picker
            set -l auto_name 0
            if test -z "$name"
              if set -q TMUX
                set -l current (command tmux display-message -p '#{session_name}')
                if string match -q '*/*' -- "$current"
                  set name (string split -m 1 '/' -- "$current")[2]
                  set auto_name 1
                end
              end
            end

            if test -z "$name"
              set wt_dir "$wt_base/$repo_name.worktrees"
              if not test -d "$wt_dir"; or test (count (command ls "$wt_dir" 2>/dev/null)) -eq 0
                echo "wtrm: no worktrees found"
                return 1
              end

              set name (command ls "$wt_dir" | fzf --prompt="remove> " --height=40%)
              or return 1
            end

            set wt_path "$wt_base/$repo_name.worktrees/$name"

            if not test -d "$wt_path"
              echo "wtrm: no worktree found for '$name'"
              return 1
            end

            # Confirm when name was auto-detected from session
            if test $auto_name -eq 1
              read -P "wtrm: remove worktree '$name'? [y/N] " confirm
              if not string match -qi 'y' -- "$confirm"
                return 0
              end
            end

            # Detect if we're removing our own session (self-remove)
            set -l self_rm 0
            set -l current_session ""
            set -l parent_session ""
            if set -q TMUX
              set current_session (command tmux display-message -p '#{session_name}')
              set -l target_session (command tmux list-sessions -F '#{session_name}' | grep "/$name\$" | head -1)
              if test -n "$target_session" -a "$current_session" = "$target_session"
                set self_rm 1
                set parent_session (string split -m 1 '/' -- "$current_session")[1]
              end
            end

            if test $self_rm -eq 1
              # Self-remove: need a session to return to
              if not command tmux has-session -t "=$parent_session" 2>/dev/null
                # Fall back to any other session
                set parent_session (command tmux list-sessions -F '#{session_name}' | grep -v "^$current_session\$" | head -1)
                if test -z "$parent_session"
                  echo "wtrm: no other session to switch to"
                  return 1
                end
              end

              set -l branch (git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null)

              # Pre-check for uncommitted changes (can't report errors after switching away)
              if test $force -eq 0
                if test -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)"
                  echo "wtrm: worktree has uncommitted changes — use 'wtrm --force' to force"
                  return 1
                end
              end

              # Build cleanup command (POSIX shell, runs server-side via tmux run-shell -b)
              set -l cleanup "tmux kill-session -t '=$current_session'"
              if test $force -eq 1
                set cleanup "$cleanup; git -C '$main_root' worktree remove --force '$wt_path'"
              else
                set cleanup "$cleanup; git -C '$main_root' worktree remove '$wt_path'"
              end
              if test -n "$branch" -a "$branch" != "HEAD"
                if test $force -eq 1
                  set cleanup "$cleanup; git -C '$main_root' branch -D '$branch' 2>/dev/null"
                else
                  set cleanup "$cleanup; git -C '$main_root' branch -d '$branch' 2>/dev/null"
                end
              end

              # Switch to parent, then schedule cleanup in background
              command tmux switch-client -t "=$parent_session"
              command tmux run-shell -b "$cleanup"
            else
              # Regular remove (from a different session)
              if set -q TMUX
                set -l target_session (command tmux list-sessions -F '#{session_name}' | grep "/$name\$" | head -1)
                if test -n "$target_session"
                  command tmux kill-session -t "=$target_session"
                end
              end

              set -l branch (git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null)

              if test $force -eq 1
                git worktree remove --force "$wt_path"
              else
                git worktree remove "$wt_path"
              end
              or begin; echo "wtrm: worktree has changes — use 'wtrm --force $name' to force"; return 1; end

              if test -n "$branch" -a "$branch" != "HEAD"
                if test $force -eq 1
                  git branch -D "$branch" 2>/dev/null
                else
                  git branch -d "$branch" 2>/dev/null
                end
                and echo "Removed worktree '$name' and branch '$branch'"
                or echo "Removed worktree '$name' (branch '$branch' not fully merged — use 'wtrm --force $name' to force)"
              else
                echo "Removed worktree '$name'"
              end
            end
          '';
        }
        // lib.optionalAttrs userCfg.linear.enable {
          wtl = ''
            _git_clean_stale_lock

            set issue_id $argv[1]

            # No args: gum picker from your Linear issues
            if test -z "$issue_id"
              set -l selection (lin list | gum filter --header "Select issue")
              or return 1
              set issue_id (string match -r '[A-Z]+-\d+' -- $selection)
            end

            # Get worktree name (2nd arg or prompt)
            set name $argv[2]
            if test -z "$name"
              set name (gum input --placeholder "worktree name" --header "Worktree")
              or return 1
              if test -z "$name"
                echo "wtl: name required"
                return 1
              end
            end

            if not set -q TMUX
              echo "wtl: requires tmux"
              return 1
            end

            set parent_session (command tmux display-message -p '#{session_name}' | string split -m 1 '/')[1]
            set session_name "$parent_session/$name"

            # Session already exists: just switch
            if command tmux has-session -t "=$session_name" 2>/dev/null
              command tmux switch-client -t "=$session_name"
              return 0
            end

            # Start issue — marks In Progress and gets branch name
            linear-cli i update $issue_id --state "In Progress" --assignee me
            or return 1
            set branch_name (lin branch $issue_id)

            # Create worktree (custom name) with Linear's branch
            wt $name $branch_name
          '';

          wtlc = ''
            _git_clean_stale_lock

            if not set -q TMUX
              echo "wtlc: requires tmux"
              return 1
            end

            set -l mode create
            if test "$argv[1]" = ai
              set mode ai
              set -e argv[1]
            end

            # Delegate issue creation to lin (create or ai)
            if test "$mode" = ai
              lin ai $argv
            else
              lin create $argv
            end
            or return 1

            set -l issue_id $_lin_ai_last_issue
            if test -z "$issue_id"
              echo "wtlc: no issue created" >&2
              return 1
            end

            # Prompt for worktree name
            set -l name (gum input --placeholder "worktree name" --header "Worktree")
            or return 1
            if test -z "$name"
              echo "wtlc: name required"
              return 1
            end

            set parent_session (command tmux display-message -p '#{session_name}' | string split -m 1 '/')[1]
            set session_name "$parent_session/$name"

            # Session already exists: just switch
            if command tmux has-session -t "=$session_name" 2>/dev/null
              command tmux switch-client -t "=$session_name"
              return 0
            end

            # Start issue — marks In Progress and gets branch name
            linear-cli i update $issue_id --state "In Progress" --assignee me
            or return 1
            set branch_name (lin branch $issue_id)

            # Create worktree with Linear's branch
            wt $name $branch_name
          '';
        }
        // lib.optionalAttrs userCfg.av.enable {
          # Stacked worktrees via av (Aviator). A stack is a tree of branches,
          # each living in its own sandboxed worktree. av tracks the parent of
          # each branch (shared metadata in the common git dir), so PRs target
          # their parent and a fix on an upstream branch can cascade-rebase the
          # downstream worktrees. Cross-worktree restack is driven by path with
          # `av -C <path>` so each sandbox is rebased in place.
          wts = ''
            set -l sub $argv[1]
            set -e argv[1]

            set -l main_root (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
            if test -z "$main_root"
              echo "wts: not a git repo" >&2
              return 1
            end
            set -l repo_name (basename $main_root)
            set -l wt_base (dirname $main_root)

            switch "$sub"
              case "" tree
                av tree $argv

              case fork
                # wts fork <name> [branch] — child worktree stacked on current branch
                set -l name $argv[1]
                if test -z "$name"
                  echo "wts fork: usage: wts fork <name> [branch]" >&2
                  return 1
                end
                set -l parent (git rev-parse --abbrev-ref HEAD 2>/dev/null)
                if test -z "$parent" -o "$parent" = HEAD
                  echo "wts fork: detached HEAD — checkout the parent branch first" >&2
                  return 1
                end
                set -l branch $argv[2]
                test -z "$branch"; and set branch $name
                set -l wt_path "$wt_base/$repo_name.worktrees/$name"

                # Create the stacked worktree+branch off the current (parent) branch.
                wt $name $branch
                or return 1

                # Register the stack edge so PRs target the parent. Adopt needs
                # at least one commit; on an empty fork it's a no-op until the
                # first commit, so don't treat failure as fatal.
                if not av -C "$wt_path" adopt --parent "$parent" 2>/dev/null
                  echo "wts: '$branch' forked from '$parent'. After your first commit, run 'wts adopt $parent' to register the stack." >&2
                end

              case adopt
                # wts adopt [parent] — register current branch as a child of <parent>
                set -l parent $argv[1]
                if test -z "$parent"
                  set -l cur (git rev-parse --abbrev-ref HEAD 2>/dev/null)
                  set parent (git branch --format='%(refname:short)' | grep -v "^$cur\$" | fzf --prompt="parent> " --height=40%)
                  or return 1
                end
                av adopt --parent "$parent"

              case restack
                # Rebase the current branch onto its parent, then cascade into
                # descendant worktrees (ordered by ancestry) so each sandbox is
                # restacked onto its freshly-updated upstream.
                set -l cur (git rev-parse --abbrev-ref HEAD 2>/dev/null)
                if test -z "$cur" -o "$cur" = HEAD
                  echo "wts restack: detached HEAD" >&2
                  return 1
                end
                set -l base_old (git rev-parse HEAD)

                av restack --current
                or begin
                  echo "wts restack: conflict in '$cur' — resolve, then 'av restack --continue'" >&2
                  return 1
                end

                # Collect descendant worktrees (branch had base_old as ancestor),
                # captured against the OLD tip before they get rebased.
                set -l paths
                set -l branches
                set -l p ""
                for line in (git worktree list --porcelain)
                  set -l kv (string split -m 1 " " -- $line)
                  switch $kv[1]
                    case worktree
                      set p $kv[2]
                    case branch
                      set -l b (string replace "refs/heads/" "" -- $kv[2])
                      if test "$b" != "$cur"; and git merge-base --is-ancestor $base_old "$b" 2>/dev/null
                        set -a paths $p
                        set -a branches $b
                      end
                  end
                end

                # Sort ancestors-first so each parent is restacked before its child.
                set -l n (count $branches)
                for i in (seq 1 $n)
                  for j in (seq 1 (math $n - $i))
                    set -l k (math $j + 1)
                    if git merge-base --is-ancestor $branches[$k] $branches[$j] 2>/dev/null
                      set -l tb $branches[$j]
                      set branches[$j] $branches[$k]
                      set branches[$k] $tb
                      set -l tp $paths[$j]
                      set paths[$j] $paths[$k]
                      set paths[$k] $tp
                    end
                  end
                end

                for i in (seq (count $paths))
                  set -l path $paths[$i]
                  set -l br $branches[$i]
                  if test -n "$(git -C "$path" status --porcelain 2>/dev/null)"
                    echo "wts restack: '$br' has uncommitted changes — skipped (restack it manually)" >&2
                    continue
                  end
                  echo "↻ restacking $br"
                  av -C "$path" restack --current
                  or begin
                    echo "wts restack: conflict in '$br' ($path). Resolve there, then 'av -C $path restack --continue'." >&2
                    return 1
                  end
                end
                echo "✓ stack restacked"

              case sync
                # Restack the whole stack across worktrees, then push + retarget
                # every PR to its correct base. `av pr --all` pushes and fixes
                # bases without rebasing checked-out branches, so it's safe to
                # run once from the current worktree after the cascade.
                wts restack
                or return 1
                av pr --all $argv

              case pr
                # Create/update stacked PRs (each targeting its parent).
                av pr --all $argv

              case rm
                # Untrack from av + remove the worktree. Refuses if the branch
                # has stacked children, to avoid orphaning them — reparent first.
                set -l name $argv[1]
                set -l target_path (git rev-parse --show-toplevel 2>/dev/null)
                set -l target_branch (git rev-parse --abbrev-ref HEAD 2>/dev/null)
                if test -n "$name"
                  set target_path "$wt_base/$repo_name.worktrees/$name"
                  set target_branch (git -C "$target_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
                end
                set -l target_tip (git -C "$target_path" rev-parse HEAD 2>/dev/null)

                set -l kids
                set -l p ""
                for line in (git worktree list --porcelain)
                  set -l kv (string split -m 1 " " -- $line)
                  switch $kv[1]
                    case branch
                      set -l b (string replace "refs/heads/" "" -- $kv[2])
                      if test "$b" != "$target_branch"; and git merge-base --is-ancestor $target_tip "$b" 2>/dev/null
                        set -a kids $b
                      end
                  end
                end
                if test (count $kids) -gt 0
                  echo "wts rm: '$target_branch' has stacked children: $kids" >&2
                  echo "Reparent them first — in each child worktree: av reparent --parent=<new>" >&2
                  echo "Then re-run: wts rm $name" >&2
                  return 1
                end

                av -C "$target_path" orphan 2>/dev/null
                wtrm $argv

              case init
                # One-time per repo: initialise av metadata (needs a GitHub PAT),
                # then pin av.trunk to origin's default branch so a global
                # init.defaultBranch that differs from this repo's trunk
                # (e.g. main vs prod) can't mis-root stacks.
                av init $argv
                or return 1
                set -l def (git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | string replace "refs/remotes/origin/" "")
                if test -z "$def"
                  set def (gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)
                end
                if test -n "$def"
                  git config av.trunk "$def"
                  echo "wts init: av.trunk pinned to '$def'"
                end

              case land
                # Land the bottom PR of the current stack (stacks merge
                # bottom-up): merge into trunk, delete the remote branch so
                # GitHub retargets child PRs onto trunk, then sync each
                # descendant in its own worktree and remove the merged one.
                set -l avdb (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/av/av.db
                if not test -f "$avdb"
                  echo "wts land: no av metadata — run 'wts init' + adopt first" >&2
                  return 1
                end
                set -l cur (git rev-parse --abbrev-ref HEAD 2>/dev/null)
                if test -z "$cur" -o "$cur" = HEAD
                  echo "wts land: run from a stack worktree" >&2
                  return 1
                end

                # Walk down to the stack bottom (branch whose parent is trunk).
                set -l bottom $cur
                set -l hops 0
                while true
                  set -l ptrunk (jq -r --arg b "$bottom" '.branches[$b].parent.trunk // empty' "$avdb")
                  test "$ptrunk" = true; and break
                  set -l parent (jq -r --arg b "$bottom" '.branches[$b].parent.name // empty' "$avdb")
                  if test -z "$parent"
                    echo "wts land: '$bottom' is not av-tracked — wts adopt first" >&2
                    return 1
                  end
                  set bottom $parent
                  set hops (math $hops + 1)
                  if test $hops -gt 20
                    echo "wts land: parent chain too deep — metadata cycle?" >&2
                    return 1
                  end
                end

                set -l prnum (jq -r --arg b "$bottom" '.branches[$b].pullRequest.number // empty' "$avdb")
                if test -z "$prnum"
                  echo "wts land: '$bottom' has no PR — run 'wts pr' first" >&2
                  return 1
                end

                echo "Landing stack bottom: $bottom (PR #$prnum)"
                read -P "Merge PR #$prnum into trunk? [y/N] " ok
                string match -qi y -- "$ok"; or return 1

                gh pr merge $prnum -s --admin $argv
                or begin; echo "wts land: merge failed" >&2; return 1; end

                # Deleting the remote branch makes GitHub retarget child PRs
                # onto the merged PR's base (trunk) automatically.
                git push origin --delete "$bottom" 2>/dev/null
                git -C "$main_root" pull 2>/dev/null

                # Descendants of bottom in ancestry order (BFS over av.db).
                set -l pairs (jq -r '.branches[] | "\(.name)|\(.parent.name)"' "$avdb")
                set -l ordered
                set -l frontier $bottom
                while test (count $frontier) -gt 0
                  set -l next
                  for pair in $pairs
                    set -l np (string split "|" -- $pair)
                    if contains -- $np[2] $frontier
                      set -a ordered $np[1]
                      set -a next $np[1]
                    end
                  end
                  set frontier $next
                end

                # branch -> worktree path map
                set -l wtbranches
                set -l wtpaths
                set -l p ""
                for line in (git worktree list --porcelain)
                  set -l kv (string split -m 1 " " -- $line)
                  switch $kv[1]
                    case worktree
                      set p $kv[2]
                    case branch
                      set -a wtbranches (string replace "refs/heads/" "" -- $kv[2])
                      set -a wtpaths $p
                  end
                end

                for b in $ordered
                  set -l idx (contains -i -- $b $wtbranches)
                  if test -z "$idx"
                    echo "wts land: '$b' has no worktree — sync it manually later" >&2
                    continue
                  end
                  echo "↻ syncing $b"
                  av -C "$wtpaths[$idx]" sync --push=yes --prune=no
                  or begin
                    echo "wts land: conflict in '$b'. Resolve there, then 'av -C $wtpaths[$idx] sync --continue'." >&2
                    return 1
                  end
                end

                # Remove the merged worktree last: if we ARE the bottom
                # worktree, wtrm self-removes and this shell dies with it.
                set -l idx (contains -i -- $bottom $wtbranches)
                if test -n "$idx"
                  echo "✓ landed PR #$prnum — removing worktree (run 'wts sync' later to prune metadata)"
                  wtrm --force (basename $wtpaths[$idx])
                else
                  git -C "$main_root" branch -D $bottom 2>/dev/null
                  echo "✓ landed PR #$prnum (run 'wts sync' later to prune metadata)"
                end

              case sessions
                _wts_pick_session

              case help -h --help
                echo "wts — stacked worktrees (av)" >&2
                echo "" >&2
                echo "worktree-aware commands:" >&2
                echo "  wts fork <name> [branch]  fork a child worktree stacked on current branch" >&2
                echo "  wts adopt [parent]        register current branch as a child of <parent>" >&2
                echo "  wts tree                  show the stack tree (default)" >&2
                echo "  wts restack               rebase downstream worktrees onto fixed upstreams" >&2
                echo "  wts sync                  restack + push + retarget PRs" >&2
                echo "  wts pr                    create/update stacked PRs" >&2
                echo "  wts rm [name]             untrack + remove a worktree (refuses if it has children)" >&2
                echo "  wts init                  initialise av metadata for this repo (one-time)" >&2
                echo "  wts land                  merge the stack's bottom PR, retarget + restack the rest" >&2
                echo "  wts sessions              stack-aware tmux session picker" >&2
                echo "" >&2
                echo "anything else is passed straight through to av in the current worktree," >&2
                echo "e.g. 'wts next', 'wts prev', 'wts switch', 'wts log', 'wts reparent'." >&2
                echo "See 'av --help' for the full list." >&2

              case '*'
                # Passthrough: any unrecognised subcommand goes straight to av,
                # operating on the current worktree. Keeps everything under one
                # entrypoint without reimplementing av's command surface.
                av $sub $argv
            end
          '';

          # Stack-aware tmux session picker: lists sessions with their branch
          # and stack depth (from av metadata), fzf to switch. Bound to
          # prefix+s (see programs.tmux.extraConfig below) and `wts sessions`.
          _wts_pick_session = ''
            if not set -q TMUX
              echo "wts sessions: requires tmux" >&2
              return 1
            end
            # Stream rows into fzf so the picker opens instantly (rows fill in
            # as they are computed). One jq per unique av.db, cached in-memory;
            # depth walks are pure string ops afterwards.
            set -l choice (
              begin
                set -l dbs
                set -l edges
                for line in (command tmux list-sessions -F "#{session_name}|#{session_path}" | sort -t "|" -k1,1)
                  set -l parts (string split "|" -- $line)
                  set -l name $parts[1]
                  set -l path $parts[2]
                  test "$name" = pocket; and continue
                  set -l label ""
                  set -l branch (git -C "$path" branch --show-current 2>/dev/null)
                  if test -n "$branch"
                    set label $branch
                    set -l avdb (git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/av/av.db
                    if test -f "$avdb"
                      set -l di (contains -i -- "$avdb" $dbs)
                      if test -z "$di"
                        set -a dbs "$avdb"
                        set di (count $dbs)
                        for e in (jq -r '.branches[] | "\(.name)|\(.parent.name)|\(.parent.trunk // false)"' "$avdb" 2>/dev/null)
                          set -a edges "$di|$e"
                        end
                      end
                      set -l curb $branch
                      set -l depth 0
                      set -l hops 0
                      while test $hops -lt 12
                        set -l hit (string match -- "$di|$curb|*" $edges)[1]
                        test -z "$hit"; and break
                        set -l f (string split "|" -- $hit)
                        set depth (math $depth + 1)
                        test "$f[4]" = true; and break
                        set curb $f[3]
                        set hops (math $hops + 1)
                      end
                      if test $depth -gt 0
                        set label (string repeat -n $depth "· ")"↳ $branch"
                      end
                    end
                  end
                  printf "%-42s %s\n" "$name" "$label"
                end
              end | fzf --prompt="session> " --height=100% --layout=reverse --info=hidden
            )
            or return 1
            set -l target (string split -f1 " " -- (string trim $choice))
            command tmux switch-client -t "=$target"
          '';
        };

        shellInit = ''
          # Completion for wt: 1st arg = existing worktree names, 2nd arg = branches
          complete -f -c wt -n "test (count (commandline -opc)) -eq 1" -a '(
            set -l mr (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
            set -l rn (basename $mr 2>/dev/null)
            set -l wd (dirname $mr 2>/dev/null)/$rn.worktrees
            test -d $wd 2>/dev/null; and command ls $wd 2>/dev/null
          )'
          complete -f -c wt -n "test (count (commandline -opc)) -eq 2" -a '(git branch -a --format="%(refname:short)" 2>/dev/null | string replace -r "^origin/" "" | sort -u | grep -v "^HEAD")'

          # Completion for wtmv: 1st arg = existing worktree names
          complete -f -c wtmv -n "test (count (commandline -opc)) -eq 1" -a '(
            set -l mr (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
            set -l rn (basename $mr 2>/dev/null)
            set -l wd (dirname $mr 2>/dev/null)/$rn.worktrees
            test -d $wd 2>/dev/null; and command ls $wd 2>/dev/null
          )'

          # Completion for wtrm: existing worktree names + --force flag
          complete -f -c wtrm -l force -s f -d "Force remove even with uncommitted changes"
          complete -f -c wtrm -a '(
            set -l mr (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
            set -l rn (basename $mr 2>/dev/null)
            set -l wd (dirname $mr 2>/dev/null)/$rn.worktrees
            test -d $wd 2>/dev/null; and command ls $wd 2>/dev/null
          )'

          # Completion for wts: wts-native subcommands + common av passthroughs
          complete -f -c wts -n "__fish_use_subcommand" -a "fork adopt tree restack sync pr rm init land sessions help"
          complete -f -c wts -n "__fish_use_subcommand" -a "next prev switch log reparent branch commit squash reorder tidy diff fetch validate-db orphan"
          complete -f -c wts -n "__fish_seen_subcommand_from rm" -a '(
            set -l mr (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
            set -l rn (basename $mr 2>/dev/null)
            set -l wd (dirname $mr 2>/dev/null)/$rn.worktrees
            test -d $wd 2>/dev/null; and command ls $wd 2>/dev/null
          )'
        '';
      };
    };
}
