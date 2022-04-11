{ ... }:
{
  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      any-nix-shell fish --info-right | source

      set fish_cursor_default block
      set fish_cursor_insert line
    '';

    shellAliases = {
      g = "git";
      ga = "git add";
      gaa = "git add .";
      gb = "git branch";
      gc = "git commit";
      gco = "git checkout";
      gp = "git push";
      ds = "nix develop . --command fish";
    };

    functions = {
      e = "emacs &";
      pj = "cd $argv; ds";

      fish_command_not_found = "__fish_default_command_not_found_handler $argv";
      fish_user_key_bindings = "fish_vi_key_bindings";
    };
  };
}
