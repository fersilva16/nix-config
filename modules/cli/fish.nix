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
        ghpm = "gh pr merge -sd --admin $argv";
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

        wt = ''
          set git_root (git rev-parse --show-toplevel 2>/dev/null)
          or begin; echo "wt: not a git repo"; return 1; end

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
          if not test -d "$wt_path"
            git fetch origin 2>/dev/null

            if test -n "$branch"
              # Use existing branch, or create new branch from default
              if git show-ref --verify --quiet "refs/heads/$branch"
                git worktree add "$wt_path" "$branch"
              else if git show-ref --verify --quiet "refs/remotes/origin/$branch"
                git worktree add --track -b "$branch" "$wt_path" "origin/$branch"
              else
                set default_branch (git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | string replace 'refs/remotes/origin/' "")
                if test -z "$default_branch"
                  echo "wt: cannot determine default branch (run: git remote set-head origin --auto)"
                  return 1
                end
                git worktree add -b "$branch" "$wt_path" "origin/$default_branch"
              end
            else
              # New branch (named after worktree) from default branch
              set default_branch (git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | string replace 'refs/remotes/origin/' "")
              if test -z "$default_branch"
                echo "wt: cannot determine default branch (run: git remote set-head origin --auto)"
                return 1
              end
              git worktree add -b "$name" "$wt_path" "origin/$default_branch"
            end
            or begin; echo "wt: failed to create worktree"; return 1; end
            echo "Created worktree at $wt_path"
            direnv allow "$wt_path" 2>/dev/null
          end

          # Create tmux session and switch
          if set -q TMUX
            command tmux new-session -d -s "$session_name" -c "$wt_path"
            command tmux switch-client -t "=$session_name"
          else
            echo "Not in tmux — run: cd $wt_path && opencode"
          end
        '';

        wtls = "git worktree list $argv";

        wtrm = ''
          set git_root (git rev-parse --show-toplevel 2>/dev/null)
          or begin; echo "wtrm: not a git repo"; return 1; end

          set name $argv[1]

          set main_root (git worktree list --porcelain | head -1 | string replace "worktree " "")
          set repo_name (basename $main_root)
          set wt_base (dirname $main_root)

          # No arg: pick from existing worktrees
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

          # Kill tmux session if it exists
          if set -q TMUX
            set current_session (command tmux display-message -p '#{session_name}')
            set target_session (command tmux list-sessions -F '#{session_name}' | grep "/$name\$" | head -1)
            if test -n "$target_session"
              if test "$current_session" = "$target_session"
                command tmux switch-client -l 2>/dev/null; or command tmux switch-client -n
              end
              command tmux kill-session -t "=$target_session"
            end
          end

          # Remove worktree (fails if dirty, protecting uncommitted work)
          git worktree remove "$wt_path"
          or begin; echo "wtrm: worktree has changes — use 'git worktree remove --force $wt_path' to force"; return 1; end

          echo "Removed worktree '$name'"
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

        # Completion for wtrm: existing worktree names
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
