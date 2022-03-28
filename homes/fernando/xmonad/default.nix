{ pkgs, ... }:
{
  xsession = {
    enable = true;

    windowManager.xmonad = {
      enable = true;
      enableContribAndExtras = true;
      config = ./config.hs;
    };
  };

  home.packages = with pkgs; [ dmenu ];
}
