let
  family = "FiraCode Nerd Font";
in
_:
{
  programs.alacritty = {
    enable = true;

    settings = {
      font = {
        normal = {
          inherit family;
          style = "Medium";
        };

        bold = {
          inherit family;
          style = "Bold";
        };

        italic = {
          inherit family;
          style = "Italic";
        };

        bold_italic = {
          inherit family;
          style = "Bold Italic";
        };
      };
    };
  };
}
