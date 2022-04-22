{ pkgs, ... }:
let
  family = "CaskaydiaCove Nerd Font";
in
{
  programs.alacritty = {
    enable = true;

    settings = {
      font = {
        normal = {
          inherit family;
          style = "Regular";
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
