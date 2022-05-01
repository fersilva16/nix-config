{ pkgs, config, ... }:
let
  replaceColors = import ../../../lib/replaceColors.nix { inherit config; };

  extraConfig = builtins.readFile ./config.hs;
in
{
  xsession = {
    enable = true;

    initExtra = ''
      autorandr --change

      keyctl link @u @s

      xwallpaper --stretch ${config.wallpaper}
    '';

    windowManager.xmonad = {
      enable = true;
      enableContribAndExtras = true;

      config = pkgs.writeText "xmonad.hs" (replaceColors extraConfig);
    };
  };

  home.packages = with pkgs; [
    dmenu
    xwallpaper
  ];
}
