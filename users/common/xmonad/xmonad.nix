{ pkgs, config, ... }:
let
  replaceColors = import ../../../lib/replaceColors.nix { inherit config; };
  replaceWallpaper = import ../../../lib/replaceWallpaper.nix { inherit config; };

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

      config = pkgs.writeText "xmonad.hs" (replaceWallpaper (replaceColors extraConfig));
    };
  };

  home.packages = with pkgs; [
    dmenu
    xwallpaper
  ];
}
