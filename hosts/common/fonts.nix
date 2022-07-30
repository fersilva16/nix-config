{ pkgs, ... }:
{
  fonts = {
    enableDefaultFonts = false;
    fonts = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      twitter-color-emoji
      (nerdfonts.override { fonts = [ "FiraCode" ]; })
      font-awesome
    ];

    fontconfig = {
      defaultFonts = {
        sansSerif = [ "Noto Sans" "Noto Sans CJK JP" "Noto Sans CJK SC" "Noto Sans CJK TC" ];
        serif = [ "Noto Serif" "Noto Serif CJK JP" "Noto Serif CJK SC" "Noto Serif CJK TC" ];
        monospace = [ "FiraCode Nerd Font" ];
        emoji = [ "Twitter Color Emoji" ];
      };
    };
  };
}
