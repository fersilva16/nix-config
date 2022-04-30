{ pkgs, ... }:
{
  programs.doom-emacs = {
    enable = true;
    doomPrivateDir = ./doom.d;
    # emacsPackage = pkgs.emacsGcc;
  };

  home.packages = with pkgs; [
    python3

    editorconfig-core-c
  ];
}
