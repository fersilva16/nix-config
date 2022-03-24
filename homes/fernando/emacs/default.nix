{ pkgs, ... }:
{
  programs.doom-emacs = {
    enable = true;
    doomPrivateDir = ./doom.d;
    # TODO: add emacs28
    # emacsPackage = pkgs.emacs28;
  };

  services.emacs = {
    enable = true;
  };
}
