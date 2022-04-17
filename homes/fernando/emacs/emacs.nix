{ pkgs, ... }:
{
  programs.doom-emacs = {
    enable = true;
    doomPrivateDir = ./doom.d;
    emacsPackage = pkgs.emacsGcc;
  };

  services.emacs = {
    enable = true;
  };
}
