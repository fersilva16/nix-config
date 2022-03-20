{ pkgs, ... }:
{
   fonts = {
    enableDefaultFonts = true;
    fonts = with pkgs; [
      noto-fonts
      twitter-color-emoji
      nerdfonts
    ];
  };
}
