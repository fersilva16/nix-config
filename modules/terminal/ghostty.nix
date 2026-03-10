{ username, pkgs, ... }:
let
  inherit (pkgs) tmux-extras;
in
{
  home-manager.users.${username} = {
    programs.ghostty = {
      enable = true;
      enableFishIntegration = true;
      package = pkgs.ghostty-bin;

      settings = {
        command = "${tmux-extras}/bin/tmux-attach";
        theme = "Flexoki Light";

        font-family = "CaskaydiaCove Nerd Font";
        font-family-bold = "CaskaydiaCove Nerd Font";
        font-family-italic = "auto";
        font-family-bold-italic = "auto";
        font-size = 12;

        cursor-style = "bar";
        cursor-style-blink = true;
        adjust-cursor-thickness = 2;

        macos-titlebar-style = "transparent";
        window-theme = "auto";
        gtk-titlebar = false;

        window-padding-x = 8;
        window-padding-y = 8;
      };
    };
  };
}
