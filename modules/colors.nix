{ lib, ... }:
let
  colorOption = lib.mkOption {
    type = lib.types.str;
  };
in
{
  options = {
    colors = {
      bg = colorOption;
      fg = colorOption;

      bgAlt = colorOption;
      fgAlt = colorOption;

      base0 = colorOption;
      base1 = colorOption;
      base2 = colorOption;
      base3 = colorOption;
      base4 = colorOption;
      base5 = colorOption;
      base6 = colorOption;
      base7 = colorOption;
      base8 = colorOption;

      grey = colorOption;
      red = colorOption;
      orange = colorOption;
      green = colorOption;
      teal = colorOption;
      yellow = colorOption;
      blue = colorOption;
      darkBlue = colorOption;
      magenta = colorOption;
      violet = colorOption;
      cyan = colorOption;
      darkCyan = colorOption;
    };
  };
}
