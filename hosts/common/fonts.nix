{ pkgs, ... }:
{
  fonts = {
    enableDefaultFonts = true;
    fonts = with pkgs; [
      noto-fonts
      twitter-color-emoji
      (nerdfonts.override { fonts = [ "FiraCode" ]; })
    ];

    fontconfig = {
      defaultFonts = {
        sansSerif = [ "Noto Sans" ];
        serif = [ "Noto Serif" ];
        monospace = [ "FiraCode Nerd Font" ];
        emoji = [ "Twitter Color Emoji" ];
      };
    };
  };
}
