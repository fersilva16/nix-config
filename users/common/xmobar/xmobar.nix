{ config, ... }:
let
  replaceColors = import ../../../lib/replaceColors.nix { inherit config; };

  extraConfig = builtins.readFile ./xmobarrc;
in
{
  programs.xmobar = {
    enable = true;

    extraConfig = replaceColors extraConfig;
  };
}
