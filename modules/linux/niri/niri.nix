# Niri session (Wayland, scrollable tiling — replaced the hyprland/i3 trial).
#
# programs.niri auto-wires portals (gnome/gtk), gnome-keyring and the
# session file; nothing to duplicate here. Niri spawns xwayland-satellite
# automatically when it's on PATH, so X11 apps just work.
#
# Home-manager has no niri module, so config.kdl is written directly —
# niri's defaults are good; this config is deliberately minimal and only
# covers what the defaults can't know: terminal/shell choices, the
# keyd hyper chords, and the macOS-style screen-bound Alt-Tab.
#
# Keyboard layout, dead-key compose and the fcitx5 IME live in the
# keyboard part (./keyboard.nix) — toggle via niri.keyboard.enable.
#
# The desktop shell (bar/launcher/lock/notifications) is noctalia
# (modules/linux/noctalia.nix); this file wires its niri glue —
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
  # Hyper+Space — toggle between Ghostty and VSCode, mirroring the
  # Hammerspoon binding on darwin (modules/darwin/hammerspoon). Focuses an
  # existing window via niri IPC, launches the app when none exists.
  # ponytail: darwin also opens VSCode at the current tmux session's git
  # root; port that if plain focus-toggling ever feels lacking.
  ghostty-code-toggle = pkgs.writeShellApplication {
    name = "niri-ghostty-code-toggle";
    runtimeInputs = [
      pkgs.jq
      pkgs.niri
    ];
    text = ''
      focus_or_launch() {
        re=$1
        shift
        id=$(niri msg -j windows | jq -r --arg re "$re" \
          '[.[] | select((.app_id // "") | test($re; "i"))][0].id // empty')
        if [ -n "$id" ]; then
          niri msg action focus-window --id "$id"
        else
          exec "$@"
        fi
      }

      focused=$(niri msg -j focused-window | jq -r '.app_id // ""')
      case "$focused" in
        *ghostty*) focus_or_launch '^code' code ;;
        *) focus_or_launch 'ghostty' ghostty ;;
      esac
    '';
  };
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

      ''
      + lib.optionalString cfg.keyboard.enable keyboard.kdl
      + ''

        spawn-at-startup "${noctalia}"

        // Noctalia integration (docs.noctalia.dev/v4 niri page):
        // rounded corners to match the shell's look, xdg-activation quirk
        // for notification actions, overview wallpaper on the backdrop
        // (inert until "Enable overview wallpaper" is on in settings).
        window-rule {
            geometry-corner-radius 20
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
            Mod+Space   { spawn "${noctalia}" "ipc" "call" "launcher" "toggle"; }
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

            // Hyper-key chords emitted by keyd (see modules/linux/keyd.nix);
            // mirrors the Hammerspoon hyper bindings on darwin.
            Mod+Ctrl+Alt+T         { spawn "ghostty"; }
            Mod+Ctrl+Alt+F         { maximize-column; }
            Mod+Ctrl+Alt+Tab       { focus-monitor-next; }
            Mod+Ctrl+Alt+backslash { move-column-to-monitor-next; }
            Mod+Ctrl+Alt+space     { spawn "${lib.getExe ghostty-code-toggle}"; }

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
