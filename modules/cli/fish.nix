{
  username,
  pkgs,
  lib,
  ...
}:
{
  environment = {
    systemPackages = [ pkgs.fish ];
    shells = [ pkgs.fish ];
  };

  users.users.${username} = {
    shell = pkgs.fish;
  };

  programs.fish.enable = true;

  home-manager.users.${username} = {
    programs.fish = {
      enable = true;

      interactiveShellInit = ''
        ssh-add --apple-load-keychain 2> /dev/null

        set fish_cursor_default block
        set fish_cursor_insert line
        set -U fish_greeting

        fish_add_path -amP /usr/bin
        fish_add_path -amP /opt/homebrew/bin
        fish_add_path -amP /opt/local/bin
        fish_add_path -m /run/current-system/sw/bin
        fish_add_path -m /Users/fernando/.nix-profile/bin
      '';

      shellAliases = {
        g = "git";
        ga = "git add";
        gaa = "git add .";
        gb = "git branch";
        gc = "git commit";
        gp = "git push";
        ds = "nix develop . --command $SHELL";

        ls = "eza -lag";
        cat = "bat";
      };

      functions = {
        ghpc = "git push && gh pr create --fill $argv && gh pr view --web";
        ghpm = ''
          gh pr merge -s --admin $argv
          or return 1

          set main_root (git worktree list --porcelain | head -1 | string replace "worktree " "")
          set current_root (git rev-parse --show-toplevel)

          if test "$main_root" != "$current_root"; and set -q TMUX
            # In a worktree: schedule pull + cleanup in parent session, then switch
            set wt_name (basename $current_root)
            set parent_session (command tmux display-message -p '#{session_name}' | string split -m 1 '/')[1]
            command tmux send-keys -t "=$parent_session" "git pull && wtrm $wt_name" Enter
            command tmux switch-client -t "=$parent_session"
          else
            # On main or not in tmux: just pull
            git pull
          end
        '';
        ghpcm = "ghpc $argv && ghpm";

        pj = "cd $argv; ds";

        fish_command_not_found = "__fish_default_command_not_found_handler $argv";

        gco = ''
          set current_branch (git rev-parse --abbrev-ref HEAD)
          git checkout $argv; and if not string match -q -- '-*' $argv && test "$current_branch" != "$argv"
            git pull
          end
        '';

        envsource = ''
          for line in (cat $argv | grep -v '^#' | grep -v '^\s*$')
            set item (string trim $line | string replace -r '\s*=\s*' '=' | string split -m 1 '=')
            set -gx $item[1] $item[2]
            echo \"Exported key $item[1]\"
          end
        '';

        _git_clean_stale_lock = ''
          set -l git_dir (git rev-parse --git-dir 2>/dev/null)
          or return 0
          set -l lock "$git_dir/index.lock"
          if test -f "$lock"
            if not lsof "$lock" >/dev/null 2>&1
              rm -f "$lock"
              echo "Removed stale index.lock"
            end
          end
        '';

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

        lin = ''
          if test (count $argv) -eq 0
            linear issue view
          else
            linear issue $argv
          end
        '';

        wtl = ''
          _git_clean_stale_lock

          set issue_id $argv[1]

          # No args: fzf picker from your Linear issues
          if test -z "$issue_id"
            set -l selection (linear issue list --no-pager 2>/dev/null | fzf --ansi --prompt="issue> " --height=40%)
            or return 1
            set issue_id (string match -r '[A-Z]+-\d+' -- $selection)
          end

          # Get worktree name (2nd arg or prompt)
          set name $argv[2]
          if test -z "$name"
            read -P "worktree name> " name
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

          # Start issue — marks In Progress and creates Linear's branch
          set original_branch (git rev-parse --abbrev-ref HEAD)
          linear issue start $issue_id
          or return 1
          set branch_name (git rev-parse --abbrev-ref HEAD)
          git checkout $original_branch 2>/dev/null

          # Create worktree (custom name) with Linear's branch
          wt $name $branch_name
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
            # Self-remove: parent session must exist to return to
            if not command tmux has-session -t "=$parent_session" 2>/dev/null
              echo "wtrm: parent session '$parent_session' not found"
              return 1
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
      };

      shellInit = ''
        # Completion for gco function
        complete -f -c gco -a '(git branch --all | string replace -r "^[\*\s]+" "" | string replace -r "^remotes/" "")'

        # Completion for wt: 1st arg = existing worktree names, 2nd arg = branches
        complete -f -c wt -n "test (count (commandline -opc)) -eq 1" -a '(
          set -l mr (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
          set -l rn (basename $mr 2>/dev/null)
          set -l wd (dirname $mr 2>/dev/null)/$rn.worktrees
          test -d $wd 2>/dev/null; and command ls $wd 2>/dev/null
        )'
        complete -f -c wt -n "test (count (commandline -opc)) -eq 2" -a '(git branch -a --format="%(refname:short)" 2>/dev/null | string replace -r "^origin/" "" | sort -u | grep -v "^HEAD")'

        # Completion for lin: linear issue subcommands
        complete -f -c lin -n "test (count (commandline -opc)) -eq 1" -a "view list start create pr"

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
