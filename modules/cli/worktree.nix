{
  mkUserModule,
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

          wtls = "git worktree list $argv";

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

          # Completion for wtrm: existing worktree names + --force flag
          complete -f -c wtrm -l force -s f -d "Force remove even with uncommitted changes"
          complete -f -c wtrm -a '(
            set -l mr (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
            set -l rn (basename $mr 2>/dev/null)
            set -l wd (dirname $mr 2>/dev/null)/$rn.worktrees
            test -d $wd 2>/dev/null; and command ls $wd 2>/dev/null
          )'
        '';
      };
    };
}
