{ pkgs, config, ... }:
let
  replaceColors = import ../../../lib/replaceColors.nix { inherit config; };

  theme = builtins.readFile ./theme.css;
in
{
  home.packages = with pkgs; [
    ytmdesktop
  ];

  home.file.".config/youtube-music-desktop-app/custom/css/page.css" = {
    text = replaceColors theme;
  };
}
