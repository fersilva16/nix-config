{ pkgs, ... }:
{
  programs.doom-emacs = {
    enable = true;
    doomPrivateDir = ./doom.d;
    emacsPackage = pkgs.emacsUnstable;
  };

  services.emacs = {
    enable = true;
  };
}
