# Hyprland session (Wayland, primary trial — i3 is the X11 fallback).
#
# programs.hyprland auto-wires xdg-desktop-portal-hyprland, polkit and
# xwayland; nothing to duplicate here. Config is deliberately minimal —
# keybindings and aesthetics iterate on real hardware.
#
# Hyprland 0.55 replaced hyprlang with Lua config; HM renders `settings`
# to hyprland.lua (each key → hl.<key>(...) call, `_args` → multi-arg
# call, mkLuaInline → raw expression). The old "$mod"/"combo, dispatcher"
# string idioms are invalid there — binds are hl.bind("MOD + KEY",
# hl.dsp.<dispatcher>) calls, and the mod "variable" is a Nix let.
{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "hyprland";
  system.programs.hyprland.enable = true;
  home =
    { lib, ... }:
    let
      mod = "SUPER";
      mkBind = combo: dispatcher: {
        _args = [
          combo
          (lib.generators.mkLuaInline dispatcher)
        ];
      };
    in
    {
      wayland.windowManager.hyprland = {
        enable = true;
        settings = {
          bind = [
            (mkBind "${mod} + Return" ''hl.dsp.exec_cmd("ghostty")'')
            (mkBind "${mod} + Space" ''hl.dsp.exec_cmd("fuzzel")'')
            (mkBind "${mod} + Q" "hl.dsp.window.close()")
            (mkBind "${mod} + SHIFT + L" ''hl.dsp.exec_cmd("hyprlock")'')
            (mkBind "${mod} + SHIFT + S" ''hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy')'')
          ]
          ++ lib.concatLists (
            lib.genList (
              i:
              let
                ws = toString (i + 1);
              in
              [
                (mkBind "${mod} + ${ws}" "hl.dsp.focus({ workspace = ${ws} })")
                (mkBind "${mod} + SHIFT + ${ws}" "hl.dsp.window.move({ workspace = ${ws} })")
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
