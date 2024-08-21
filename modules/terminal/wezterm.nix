{ username, pkgs, inputs, ... }:
{
  home-manager.users.${username} = {
    programs.wezterm = {
      enable = true;
      extraConfig = ''
        local wezterm = require 'wezterm'

        return {
          font = wezterm.font("CaskaydiaCove Nerd Font"),
        }
      '';
    };
  };
}
