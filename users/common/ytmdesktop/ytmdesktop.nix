{ pkgs, config, ... }:
{
  home.packages = with pkgs; [
    ytmdesktop
  ];

  home.file.".config/youtube-music-desktop-app/custom/css/page.css" = {
    text = builtins.readFile ./theme.css;
  };
}
