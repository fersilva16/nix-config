# i3 session (X11, boring fallback — hyprland is the Wayland primary).
#
# services.xserver.windowManager.i3 ships dmenu/i3status/i3lock by default;
# home-manager's i3 defaults cover workspace keybindings. Config is
# deliberately minimal — aesthetics iterate on real hardware.
{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
mkUserModule {
  name = "i3";
  system = {
    services.xserver = {
      enable = true;
      windowManager.i3.enable = true;
    };
    programs.xss-lock = {
      enable = true;
      lockerCommand = lib.getExe pkgs.i3lock;
    };
  };
  home = {
    xsession.windowManager.i3 = {
      enable = true;
      config = {
        modifier = "Mod4";
        terminal = "ghostty";
        menu = "rofi -show drun";
        keybindings = lib.mkOptionDefault {
          "Mod4+Shift+l" = "exec ${lib.getExe pkgs.i3lock}";
        };
      };
    };

    programs.rofi.enable = true;

    # ponytail: dunst and swaync both claim org.freedesktop.Notifications via
    # graphical-session.target; if they fight on hyprland, gate per-session.
    services.dunst.enable = true;

    home.packages = with pkgs; [ xclip ];
  };
}
