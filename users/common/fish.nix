_:
{
  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      ssh-add --apple-load-keychain 2> /dev/null
    
      set fish_cursor_default block
      set fish_cursor_insert line
      set -U fish_greeting

      set -gx GPG_TTY (tty)

      fish_add_path -amP /usr/bin
      fish_add_path -amP /opt/homebrew/bin
      fish_add_path -amP /opt/local/bin
      fish_add_path -m /run/current-system/sw/bin
      fish_add_path -m /Users/fernando/.nix-profile/bin

      printf '\eP$f{"hook": "SourcedRcFileForWarp", "value": { "shell": "fish"}}\x9c'
    '';


    shellAliases = {
      g = "git";
      ga = "git add";
      gaa = "git add .";
      gb = "git branch";
      gc = "git commit";
      gco = "git checkout";
      gp = "git push";
      ds = "nix develop . --command $SHELL";

      ls = "eza -lag";
      cat = "bat";

      ghpc = "gh pr create --fill && gh pr view --web";
      ghpm = "gh pr merge -sd --admin";
      ghpcm = "ghpc && ghpm";
    };

    functions = {
      pj = "cd $argv; ds";

      fish_command_not_found = "__fish_default_command_not_found_handler $argv";

      envsource = "
        for line in (cat $argv | grep -v '^#' | grep -v '^\\s*$')
          set item (string split -m 1 '=' $line)
          set -gx $item[1] $item[2]
          echo \"Exported key $item[1]\"
        end
      ";
    };
  };
}
