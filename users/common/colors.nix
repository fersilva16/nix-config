{ config, ... }:
{
  imports = [
    ../../modules/colors.nix
  ];

  colors = {
    bg = "#282c34";
    fg = "#bbc2cf";

    bgAlt = "#21242b";
    fgAlt = "#5b6268";

    base0 = "#1b2229";
    base1 = "#1c1f24";
    base2 = "#202328";
    base3 = "#23272e";
    base4 = "#3f444a";
    base5 = "#5b6268";
    base6 = "#73797e";
    base7 = "#9ca0a4";
    base8 = "#dfdfdf";

    grey = config.colors.base4;
    red = "#ff6c6b";
    orange = "#da8548";
    green = "#98be65";
    teal = "#4db5bd";
    yellow = "#ecbe7b";
    blue = "#51afef";
    darkBlue = "#2257a0";
    magenta = "#c678dd";
    violet = "#a9a1e1";
    cyan = "#46d9ff";
    darkCyan = "#5699af";
  };
}
