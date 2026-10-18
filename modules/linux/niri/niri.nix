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
    { cfg, userCfg, ... }:
    let
      # niri spawn of a noctalia IPC call: ipc "volume increase".
      ipc = call: ''spawn "${noctalia}" "ipc" "call" "${lib.replaceStrings [ " " ] [ ''" "'' ] call}"'';
      recorder = userCfg.noctalia.enable && userCfg.noctalia.screen-recorder.enable;

      # Cmd+Shift+5 — the macOS capture toolbar as a vicinae list: the three
      # screenshot modes, plus recording through noctalia's recorder plugin
      # (the portal picker then chooses a monitor or a window).
      capture-menu = pkgs.writeShellApplication {
        name = "niri-capture-menu";
        runtimeInputs = [
          pkgs.niri
          pkgs.procps
        ];
        text = ''
          items="Capture Entire Screen
          Capture Selected Window
          Capture Selected Portion"
        ''
        + lib.optionalString recorder ''
          if pgrep -f gpu-screen-recorder >/dev/null; then
            items="Stop Recording
          $items"
          else
            items="$items
          Record Screen or Window"
          fi
        ''
        + ''
          choice=$(printf '%s\n' "$items" | vicinae dmenu --no-section --no-quick-look -p "Capture")
          case "$choice" in
            "Capture Entire Screen") niri msg action screenshot-screen ;;
            "Capture Selected Window") niri msg action screenshot-window ;;
            "Capture Selected Portion") niri msg action screenshot ;;
            "Record Screen or Window") ${noctalia} ipc call plugin:screen-recorder start ;;
            "Stop Recording") ${noctalia} ipc call plugin:screen-recorder stop ;;
          esac
        '';
      };
    in
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

        // polaris's monitor: its EDID-preferred mode is 60 Hz, so niri would
        // stay there. On-demand VRR only kicks in for windows whose rule
        // asks for it (games), so the desktop keeps a fixed refresh rate.
        output "Dell Inc. AW2725QF 5WQPD34" {
            mode "3840x2160@164.991"
            variable-refresh-rate on-demand=true
        }

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

        // Slower pointer. The default adaptive profile barely moves with
        // accel-speed; flat makes it a plain multiplier (speed+1, so -0.5
        // is half speed). niri allows a single input block, so the keyboard
        // part's settings are embedded here.
        input {
            mouse {
                accel-profile "flat"
                accel-speed -0.1
            }
      ''
      + lib.optionalString cfg.keyboard.enable keyboard.inputKdl
      + ''
        }

        // Slightly dim unfocused windows so the active one reads at a glance.
        // niri has no real dim: the border is drawn as a solid rectangle
        // behind the window (its dark inactive color), so the lowered opacity
        // blends the window with that instead of showing the wallpaper.
        // The border is already on for every window, so sizes don't change.
        window-rule {
            match is-active=false
            opacity 0.9
            draw-border-with-background true
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

            Mod+Return  { spawn "limi-desktop"; }
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

            // macOS capture keys (Cmd = Mod, kept Super by the xremap mac
            // part): 3 whole screen, 4 region, 5 the capture menu. niri saves
            // to ~/Pictures/Screenshots and copies to the clipboard.
            Print       { screenshot; }
            Mod+Shift+S { screenshot; }
            Mod+Shift+3 { screenshot-screen; }
            Mod+Shift+4 { screenshot; }
      ''
      + lib.optionalString userCfg.vicinae.enable ''
        Mod+Shift+5 { spawn "${lib.getExe capture-menu}"; }
      ''
      + lib.optionalString recorder ''
        // Cmd+Ctrl+Esc stops a recording, as on macOS.
        Mod+Ctrl+Escape { ${ipc "plugin:screen-recorder stop"}; }
      ''
      + ''

            // Media keys through noctalia so its volume OSD shows. They come
            // from the receiver's Consumer Control device, which xremap
            // doesn't grab, so they reach niri untouched.
            XF86AudioRaiseVolume allow-when-locked=true { ${ipc "volume increase"}; }
            XF86AudioLowerVolume allow-when-locked=true { ${ipc "volume decrease"}; }
            XF86AudioMute        allow-when-locked=true { ${ipc "volume muteOutput"}; }
            XF86AudioMicMute     allow-when-locked=true { ${ipc "volume muteInput"}; }
            XF86AudioPlay        allow-when-locked=true { ${ipc "media playPause"}; }
            XF86AudioPause       allow-when-locked=true { ${ipc "media playPause"}; }
            XF86AudioStop        allow-when-locked=true { ${ipc "media stop"}; }
            XF86AudioNext        allow-when-locked=true { ${ipc "media next"}; }
            XF86AudioPrev        allow-when-locked=true { ${ipc "media previous"}; }

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
        events = {
          before-sleep = "loginctl lock-session";
          lock = "${noctalia} ipc call lockScreen lock";
        };
      };

      home.packages = with pkgs; [ wl-clipboard ];
    };
}
