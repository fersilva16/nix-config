{ username, pkgs, ... }:
{
  home-manager.users.${username} = {
    programs.kitty = {
      enable = true;
      shellIntegration.enableFishIntegration = true;

      themeFile = "flexoki_light";

      settings = {
        disable_ligatures = "never";
        cursor_shape = "beam";

        tab_bar_style = "powerline";

        font_family = "CaskaydiaCove Nerd Font";
        bold_font = "CaskaydiaCove Nerd Font";
        italic_font = "auto";
        bold_italic_font = "auto";
        font_size = 12;

        macos_titlebar_color = "#FFFCF0";
        macos_show_window_title_in = "none";
      };
    };
  };
}
