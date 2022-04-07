{ ... }:

{
  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      any-nix-shell fish --info-right | source
    '';

    shellAliases = {
      g = "git";
    };

    functions = {
      e = "emacs &";
    };
  };
}
