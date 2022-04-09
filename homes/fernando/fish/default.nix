{ ... }:

{
  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      any-nix-shell fish --info-right | source
    '';

    shellAliases = {
      g = "git";
      ga = "git add";
      gaa = "git add .";
      gb = "git branch";
      gc = "git commit";
      gco = "git checkout";
      gp = "git push";
      e = "emacs &";
      ds = "nix develop . --command fish";
    };

    functions = {
      pj = "cd $argv; ds";
    };
  };
}
