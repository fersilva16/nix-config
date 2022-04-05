{ pkgs, ... }:
{
   fonts = {
    enableDefaultFonts = true;
    fonts = with pkgs; [
      noto-fonts
      twitter-color-emoji
      (nerdfonts.override { fonts = [ "CascadiaCode" ]; })
    ];

    fontconfig = {
      defaultFonts = {
        sansSerif = [ "Noto Sans" ];
        serif = [ "Noto Serif" ];
        monospace = [ "Caskadia Cove Nerd Font" ];
        emoji = [ "Twitter Color Emoji" ];
      };
    };
  };
}
