{ ... }:
{
  services.xserver = {
    enable = true;
    layout = "br-abnt2";

    displayManager.startx.enable = true;

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
