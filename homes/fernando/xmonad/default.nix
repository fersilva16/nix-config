{ pkgs, ... }:
{
  xsession = {
    enable = true;

    initExtra = ''
      xrandr --output eDP-1-1 --mode 1920x1080 --rate 144 --primary
      xrandr --output HDMI-0 --mode 1920x1080  --rate 60 --left-of eDP-1-1
    '';

    windowManager.xmonad = {
      enable = true;
      enableContribAndExtras = true;
      config = ./config.hs;
    };
  };

  home.packages = with pkgs; [ dmenu ];
}
