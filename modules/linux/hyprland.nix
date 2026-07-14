# Hyprland session (Wayland, primary trial — i3 is the X11 fallback).
#
# programs.hyprland auto-wires xdg-desktop-portal-hyprland, polkit and
# xwayland; nothing to duplicate here. Config is deliberately minimal —
# keybindings and aesthetics iterate on real hardware.
{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "hyprland";
  system.programs.hyprland.enable = true;
  home =
    { lib, ... }:
    {
      wayland.windowManager.hyprland = {
        enable = true;
        settings = {
          "$mod" = "SUPER";
          bind = [
            "$mod, Return, exec, ghostty"
            "$mod, Space, exec, fuzzel"
            "$mod, Q, killactive"
            "$mod SHIFT, L, exec, hyprlock"
            "$mod SHIFT, S, exec, grim -g \"$(slurp)\" - | wl-copy"
          ]
          ++ lib.concatLists (
            lib.genList (
              i:
              let
                ws = toString (i + 1);
              in
              [
                "$mod, ${ws}, workspace, ${ws}"
                "$mod SHIFT, ${ws}, movetoworkspace, ${ws}"
              ]
            ) 9
          );
        };
      };

      programs = {
        waybar.enable = true;
        fuzzel.enable = true;
        hyprlock.enable = true;
      };
      services.swaync.enable = true;
      services.hypridle = {
        enable = true;
        settings = {
          general = {
            lock_cmd = "pidof hyprlock || hyprlock";
            before_sleep_cmd = "loginctl lock-session";
          };
          listener = [
            {
              timeout = 600;
              on-timeout = "loginctl lock-session";
            }
            {
              timeout = 900;
              on-timeout = "hyprctl dispatch dpms off";
              on-resume = "hyprctl dispatch dpms on";
            }
          ];
        };
      };

      home.packages = with pkgs; [
        grim
        slurp
        wl-clipboard
        cliphist
      ];
    };
}
