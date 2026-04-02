{ mkUserModule, ... }:
mkUserModule {
  name = "wezterm";
  home.programs.wezterm = {
    enable = true;
    extraConfig = ''
      local wezterm = require 'wezterm'

      return {
        font = wezterm.font("CaskaydiaCove Nerd Font"),
      }
    '';
  };
}
