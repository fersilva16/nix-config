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

      export XMODIFIERS="@im=fcitx"
      export XMODIFIER="@im=fcitx"
      export GTK_IM_MODULE="fcitx"
      export QT_IM_MODULE="fcitx"

      fcitx &
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
