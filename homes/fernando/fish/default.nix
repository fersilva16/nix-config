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
    };

    functions = {
      e = "emacs &";
    };
  };
}
