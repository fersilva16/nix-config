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
      };

      shellInit = ''
        # Completion for gco function
        complete -f -c gco -a '(git branch --all | string replace -r "^[\*\s]+" "" | string replace -r "^remotes/" "")'
      '';
    };
  };
}
