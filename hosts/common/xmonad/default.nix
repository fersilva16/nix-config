{ ... }:
{
  services.xserver = {
    enable = true;
    layout = "br,us";
    xkbVariant = "abnt2,";

    displayManager = {
      defaultSession = "none+xmonad";
      startx.enable = true;
    };

    windowManager.xmonad = {
      enable = true;
      enableContribAndExtras = true;
      extraPackages = haskellPackages: with haskellPackages; [
        xmonad
        xmonad-contrib
        xmonad-extras
        xmobar
      ];
    };
  };
}
