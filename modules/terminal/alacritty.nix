{ username, pkgs, ... }:
let
  family = "CaskaydiaCove Nerd Font";
in
{
  home-manager.users.${username} = {
    programs.alacritty = {
      enable = true;

      settings = {
        import = [ "${pkgs.alacritty-theme}/catppuccin.toml" ];

        cursor = {
          style = {
            shape = "Beam";
            blinking = "On";
          };
        };

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
  };
}
