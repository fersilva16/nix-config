{ pkgs, ... }:
{
  programs.doom-emacs = {
    enable = true;
    doomPrivateDir = ./doom.d;
    # emacsPackage = pkgs.emacsGcc;
  };

  home.packages = with pkgs; [
    # Used by treemacs
    python3

    editorconfig-core-c
  ];

  # services.emacs = {
  #   enable = true;
  # };
}
