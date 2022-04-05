{ ... }:

{
  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      any-nix-shell fish --info-right | source
    '';

    shellAbbrs = {
      g = "git";
    };

    functions = {
      e = "emacs &";
    };
  };
}
