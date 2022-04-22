{ ... }:
{
  programs.kitty = {
    enable = true;

    font = {
      name = "CaskaydiaCove Nerd Font";
    };

    theme = "Doom One";

    settings = {
      disable_ligatures = "never";
      cursor_shape = "beam";

      tab_bar_style = "powerline";
    };
  };
}
