# Hyper part — Linux port of the modules/darwin/hammerspoon hyper key.
#
# Hold Caps = hyper layer, tap Caps = Caps Lock. hjkl→arrows works in every
# app, and real modifiers pass through (inexact match), so hyper+shift+h
# selects left just like on macOS. Physical arrows are blocked to force
# hjkl, same as the Hammerspoon arrowBlocker — bare presses only, so
# modifier+arrow chords still work.
#
# Window actions run `niri msg action` directly via xremap's launch, so
# hyper owns them end to end (only when niri is enabled).
{
  pkgs,
  lib,
  yaml,
  hyperKey,
}:
let
  niri = lib.getExe pkgs.niri;
  action = args: {
    launch = [
      niri
      "msg"
      "action"
    ]
    ++ args;
  };

  # Hyper+Space — toggle between Ghostty and VSCode, mirroring the
  # Hammerspoon binding on darwin. Focuses an existing window via niri IPC,
  # launches the app when none exists.
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
          niri msg action spawn -- "$@"
        fi
      }

      focused=$(niri msg -j focused-window | jq -r '.app_id // ""')
      case "$focused" in
        *ghostty*) focus_or_launch '^code' code ;;
        *) focus_or_launch 'ghostty' ghostty ;;
      esac
    '';
  };

  windowActions = {
    "${hyperKey}-t" = action [
      "spawn"
      "--"
      "ghostty"
    ];
    "${hyperKey}-f" = action [ "maximize-column" ];
    "${hyperKey}-tab" = action [ "focus-monitor-next" ];
    "${hyperKey}-backslash" = action [ "move-column-to-monitor-next" ];
    "${hyperKey}-space".launch = [ (lib.getExe ghostty-code-toggle) ];
  };
in
{
  home =
    { userCfg, ... }:
    {
      xdg.configFile."xremap/hyper.yml".source = yaml.generate "xremap-hyper.yml" {
        modmap = [
          {
            name = "Hyper: tap for Caps Lock";
            # F18 is a Mac's Caps Lock (hammerspoon's hidutil remap), as it
            # arrives over lan-mouse from vega.
            remap = lib.genAttrs [ hyperKey "F18" ] (_: {
              held = hyperKey;
              alone = "BTN_TRIGGER_HAPPY1";
            });
          }
        ];
        virtual_modifiers = [ hyperKey ];
        keymap = [
          {
            name = "Hyper";
            remap = {
              BTN_TRIGGER_HAPPY1 = "CapsLock";
              "${hyperKey}-h" = "left";
              "${hyperKey}-j" = "down";
              "${hyperKey}-k" = "up";
              "${hyperKey}-l" = "right";
              "${hyperKey}-semicolon" = "end"; # macOS Cmd+Right ≈ end of line
            }
            // lib.optionalAttrs userCfg.niri.enable windowActions;
          }
          {
            name = "Force hjkl: block bare arrows";
            exact_match = true;
            remap = {
              left = [ ];
              right = [ ];
              up = [ ];
              down = [ ];
            };
          }
        ];
      };
    };
}
