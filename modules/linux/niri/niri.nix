# Niri session (Wayland, scrollable tiling — replaced the hyprland/i3 trial).
#
# programs.niri auto-wires portals (gnome/gtk), gnome-keyring and the
# session file; nothing to duplicate here. Niri spawns xwayland-satellite
# automatically when it's on PATH, so X11 apps just work.
#
# Home-manager has no niri module, so config.kdl is written directly —
# niri's defaults are good; this config is deliberately minimal and only
# covers what the defaults can't know: terminal/shell choices, the
# the macOS-style screen-bound Alt-Tab.
#
# Keyboard layout, dead-key compose and the fcitx5 IME live in the
# keyboard part (./keyboard.nix) — toggle via niri.keyboard.enable.
#
# The desktop shell (bar/lock/notifications) is noctalia; the app launcher
# is vicinae (modules/productivity/vicinae), which binds Mod+Space. For
# noctalia (modules/linux/noctalia/noctalia.nix) this file wires the niri glue —
# spawn-at-startup, IPC keybinds, layer rules.
{
  mkUserModule,
  pkgs,
  lib,
  inputs,
  system,
  ...
}:
let
  noctalia = "${inputs.noctalia.packages.${system}.default}/bin/noctalia-shell";
  keyboard = import ./keyboard.nix { inherit pkgs lib; };
in
mkUserModule {
  name = "niri";
  parts = {
    inherit keyboard;
  };
  system = {
    programs.niri.enable = true;
    environment.systemPackages = [ pkgs.xwayland-satellite ];
  };
  home =
    { cfg, ... }:
    {
      xdg.configFile."niri/config.kdl".text = ''
        hotkey-overlay {
            skip-at-startup
        }

        // Full-width windows by default — one window fills the screen, the
        // rest sit off-screen in the strip, reached via Alt-Tab (vega-style).
        // "Ink" look (palette shared with noctalia's Ink scheme in
        // modules/linux/noctalia/noctalia.nix): edge-to-edge windows (no gaps,
        // no wallpaper between them), square corners, and a hairline bone
        // border instead of the glowy focus ring. Static; no animations.
        prefer-no-csd

        layout {
            default-column-width { proportion 1.0; }
            gaps 0
            background-color "#0a0a0a"
            focus-ring {
                off
            }
            border {
                on
                width 2
                active-color "#e8e2d4"
                inactive-color "#3a3833"
                urgent-color "#b23a2e"
            }
        }

        overview {
            backdrop-color "#0a0a0a"
        }

        // Fade unfocused windows so the active one reads at a glance
        // (mostly visible in the overview and with split columns).
        window-rule {
            match is-active=false
            opacity 0.88
        }

      ''
      + lib.optionalString cfg.keyboard.enable keyboard.kdl
      + ''

        spawn-at-startup "${noctalia}"

        // Noctalia integration (docs.noctalia.dev/v4 niri page):
        // square corners to match the shell's Ink look (radiusRatio 0),
        // xdg-activation quirk for notification actions, overview wallpaper
        // on the backdrop (inert until "Enable overview wallpaper" is on).
        window-rule {
            geometry-corner-radius 0
            clip-to-geometry true
        }

        debug {
            honor-xdg-activation-with-invalid-serial
        }

        layer-rule {
            match namespace="^noctalia-overview*"
            place-within-backdrop true
        }

        // Alt-Tab bound to the current monitor — mirrors AltTab on macOS
        // (modules/darwin/alt-tab). Alt+grave cycles the focused app's windows.
        // Mod variants are left Cmd (xremap mac part leaves Cmd+Tab as Super),
        // so holding Cmd keeps the switcher open like AltTab.
        recent-windows {
            binds {
                Alt+Tab         { next-window     scope="output"; }
                Alt+Shift+Tab   { previous-window scope="output"; }
                Alt+grave       { next-window     filter="app-id"; }
                Alt+Shift+grave { previous-window filter="app-id"; }
                Mod+Tab         { next-window     scope="output"; }
                Mod+Shift+Tab   { previous-window scope="output"; }
                Mod+grave       { next-window     filter="app-id"; }
                Mod+Shift+grave { previous-window filter="app-id"; }
            }
        }

        binds {
            Mod+Shift+Slash { show-hotkey-overlay; }

            Mod+Return  { spawn "ghostty"; }
            Mod+S       { spawn "${noctalia}" "ipc" "call" "controlCenter" "toggle"; }
            Mod+Q       { close-window; }
            Mod+Shift+L { spawn "${noctalia}" "ipc" "call" "lockScreen" "lock"; }
            Mod+O       { toggle-overview; }

            Mod+Left        { focus-column-left; }
            Mod+Right       { focus-column-right; }
            Mod+Up          { focus-window-up; }
            Mod+Down        { focus-window-down; }
            Mod+Shift+Left  { move-column-left; }
            Mod+Shift+Right { move-column-right; }

            Mod+R       { switch-preset-column-width; }
            Mod+F       { maximize-column; }
            Mod+Shift+F { fullscreen-window; }

            Print       { screenshot; }
            Mod+Shift+S { screenshot; }

            Mod+Shift+E { quit; }
        }
      '';

      # ponytail: swayidle stays for idle timeouts because noctalia's own
      # idle service defaults to off (GUI setting); drop swayidle if that
      # ever gets enabled in noctalia's settings.
      services.swayidle = {
        enable = true;
        timeouts = [
          {
            timeout = 600;
            command = "loginctl lock-session";
          }
          {
            timeout = 900;
            command = "niri msg action power-off-monitors";
          }
        ];
        events = [
          {
            event = "before-sleep";
            command = "loginctl lock-session";
          }
          {
            event = "lock";
            command = "${noctalia} ipc call lockScreen lock";
          }
        ];
      };

      home.packages = with pkgs; [ wl-clipboard ];
    };
}
