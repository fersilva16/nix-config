# Niri session (Wayland, scrollable tiling — replaced the hyprland/i3 trial).
#
# programs.niri auto-wires portals (gnome/gtk), gnome-keyring and the
# session file; nothing to duplicate here. Niri spawns xwayland-satellite
# automatically when it's on PATH, so X11 apps just work.
#
# Home-manager has no niri module, so config.kdl is written directly —
# niri's defaults are good; this config is deliberately minimal and only
# covers what the defaults can't know: terminal/launcher/lock choices, the
# keyd hyper chords, and the macOS-style screen-bound Alt-Tab.
{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
mkUserModule {
  name = "niri";
  system = {
    programs.niri.enable = true;
    environment.systemPackages = [ pkgs.xwayland-satellite ];
  };
  home = {
    xdg.configFile."niri/config.kdl".text = ''
      hotkey-overlay {
          skip-at-startup
      }

      // Alt-Tab bound to the current monitor — mirrors AltTab on macOS
      // (modules/darwin/alt-tab). Alt+grave cycles the focused app's windows.
      recent-windows {
          binds {
              Alt+Tab         { next-window     scope="output"; }
              Alt+Shift+Tab   { previous-window scope="output"; }
              Alt+grave       { next-window     filter="app-id"; }
              Alt+Shift+grave { previous-window filter="app-id"; }
          }
      }

      binds {
          Mod+Shift+Slash { show-hotkey-overlay; }

          Mod+Return  { spawn "ghostty"; }
          Mod+Space   { spawn "fuzzel"; }
          Mod+Q       { close-window; }
          Mod+Shift+L { spawn "swaylock" "-f"; }
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

    programs = {
      waybar = {
        enable = true;
        systemd.enable = true;
      };
      fuzzel.enable = true;
      swaylock.enable = true;
    };
    services.swaync.enable = true;
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
          command = "pidof swaylock || ${lib.getExe pkgs.swaylock} -f";
        }
      ];
    };

    home.packages = with pkgs; [ wl-clipboard ];
  };
}
