{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
mkUserModule {
  name = "git";
  home =
    { userCfg, ... }:
    {
      home.packages = with pkgs; [ gh ];

      programs = {
        git = {
          enable = true;
          lfs.enable = true;

          package = pkgs.git;

          settings = {
            user = {
              email = "fernandonsilva16@gmail.com";
              name = "Fernando Silva";
            };

            init = {
              defaultBranch = "main";
            };

            pull = {
              rebase = false;
            };

            push = {
              autoSetupRemote = true;
            };

            core = {
              ignorecase = false;
            };
          };
        };

        gh = {
          enable = true;
          settings.git_protocol = "ssh";
        };

        # Fish shell integration: git aliases, workflow functions, and completions
        fish = lib.mkIf userCfg.fish.enable {
          shellAliases = {
            g = "git";
            ga = "git add";
            gaa = "git add .";
            gb = "git branch";
            gc = "git commit";
            gp = "git push";
          };

          functions = {
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

            gco = ''
              set current_branch (git rev-parse --abbrev-ref HEAD)
              git checkout $argv; and if not string match -q -- '-*' $argv && test "$current_branch" != "$argv"
                git pull
              end
            '';

            ghpc = "git push && gh pr create --fill $argv && gh pr view --web";

            ghpm = ''
              set feature_branch (git rev-parse --abbrev-ref HEAD)

              gh pr merge -s --admin $argv
              or return 1

              git push origin --delete "$feature_branch" 2>/dev/null

              set main_root (git worktree list --porcelain | head -1 | string replace "worktree " "")
              set current_root (git rev-parse --show-toplevel)

              if test "$main_root" != "$current_root"; and set -q TMUX
                # In a worktree: pull main, then clean up
                git -C "$main_root" pull
                set wt_name (basename $current_root)
                wtrm --force $wt_name
              else
                # In the main repo: switch to default branch, pull, delete feature branch
                set feature_branch (git rev-parse --abbrev-ref HEAD)
                set default_branch (git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | string replace 'refs/remotes/origin/' "")
                if test -z "$default_branch"
                  set default_branch main
                end
                git checkout "$default_branch"
                git pull
                git branch -D "$feature_branch" 2>/dev/null
              end
            '';

            ghpcm = "ghpc $argv && ghpm";
          };

          shellInit = ''
            # Completion for gco function
            complete -f -c gco -a '(git branch --all | string replace -r "^[\*\s]+" "" | string replace -r "^remotes/" "")'
          '';
        };
      };
    };
}
