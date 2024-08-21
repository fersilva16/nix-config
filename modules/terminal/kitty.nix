{ username, pkgs, ... }:
{
  home-manager.users.${username} = {
    programs.kitty = {
      enable = true;
      shellIntegration.enableFishIntegration = true;

      theme = "Catppuccin-Mocha";

      settings = {
        disable_ligatures = "never";
        cursor_shape = "beam";

        tab_bar_style = "powerline";

        font_family = "CaskaydiaCove Nerd Font";
        bold_font = "CaskaydiaCove Nerd Font";
        italic_font = "auto";
        bold_italic_font = "auto";
      };
    };
  };
}
