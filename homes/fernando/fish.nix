{ ... }:
{
  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      any-nix-shell fish --info-right | source

      set fish_cursor_default block
      set fish_cursor_insert line

      set -gx GPG_TTY (tty)
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
    };

    functions = {
      ls = "exa -lag $argv";
      cat = "bat $argv";

      e = "emacs &";
      pj = "cd $argv; ds";

      fish_command_not_found = "__fish_default_command_not_found_handler $argv";
      fish_user_key_bindings = "fish_vi_key_bindings";

      notes-push = ''
        set prevdir (pwd)

        cd "$HOME/org"

        git add .
        git commit -m "$(date -u +"%Y-%m-%d %H:%M:%S")"
        git push

        cd $prevdir
      '';
    };
  };
}
