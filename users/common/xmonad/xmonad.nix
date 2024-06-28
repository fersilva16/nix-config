{ pkgs, config, ... }:
let
  extraConfig = builtins.readFile ./config.hs;
in
{
  xsession = {
    enable = true;

    initExtra = ''
      autorandr --change

      keyctl link @u @s

      fcitx5 &
    '';

    windowManager.xmonad = {
      enable = true;
      enableContribAndExtras = true;

      config = pkgs.writeText "xmonad.hs" extraConfig;
    };
  };

  home.packages = with pkgs; [
    dmenu
    xwallpaper
  ];
}
