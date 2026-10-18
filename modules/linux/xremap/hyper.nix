# Hyper part — Linux port of the modules/darwin/hammerspoon hyper key.
#
# Hold Caps = hyper layer, tap Caps = Caps Lock. hjkl→arrows works in every
# app, and real modifiers pass through (inexact match), so hyper+shift+h
# selects left just like on macOS. Physical arrows are blocked to force
# hjkl, same as the Hammerspoon arrowBlocker — bare presses only, so
# modifier+arrow chords still work.
#
# Window actions run `niri msg action` directly via xremap's launch, so
# hyper owns them end to end (only when niri is enabled). Held Caps also
# presses Ctrl_R (see `hyper` in ./xremap.nix), so keys with no rule here
# reach niri as Mod binds, as do Hyper+drag and Hyper+scroll.
{
  pkgs,
  lib,
  yaml,
  hyperKey,
  hyper,
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

  # Hyper+Space — toggle between limi-desktop and VSCode, mirroring the
  # Hammerspoon binding on darwin. Focuses an existing window via niri IPC,
  # launches the app when none exists.
  # ponytail: darwin also opens VSCode at the current tmux session's git
  # root; port that if plain focus-toggling ever feels lacking.
  terminal-code-toggle = pkgs.writeShellApplication {
    name = "niri-terminal-code-toggle";
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
        limi-desktop) focus_or_launch '^code' code ;;
        *) focus_or_launch '^limi-desktop$' limi-desktop ;;
      esac
    '';
  };

  windowActions = {
    "${hyper}-t" = action [
      "spawn"
      "--"
      "limi-desktop"
    ];
    "${hyper}-f" = action [ "maximize-column" ];
    "${hyper}-tab" = action [ "focus-monitor-next" ];
    "${hyper}-backslash" = action [ "move-column-to-monitor-next" ];
    "${hyper}-space".launch = [ (lib.getExe terminal-code-toggle) ];
  };
in
{
  # Caps Lock → F18 at the kernel, the linux twin of vega's hidutil map
  # (modules/darwin/hammerspoon). F18 has a real key-up and no lock state, so
  # hyper works and, while lan-mouse sends keys to vega with xremap stopped,
  # it crosses as F18 for Hammerspoon without toggling polaris's caps lock.
  # Applies to keyboards on connect: replug (or reboot) after a change.
  system.services.udev.extraHwdb = ''
    evdev:input:b0003*
     KEYBOARD_KEY_70039=f18
    evdev:input:b0005*
     KEYBOARD_KEY_70039=f18
  '';

  home =
    { userCfg, ... }:
    {
      xdg.configFile."xremap/hyper.yml".source = yaml.generate "xremap-hyper.yml" {
        modmap = [
          {
            name = "Hyper: tap for Caps Lock";
            # Caps Lock arrives as F18: from the hwdb above, and from vega's
            # keyboard over lan-mouse (its hidutil map). CapsLock covers any
            # keyboard the hwdb doesn't match.
            remap = lib.genAttrs [ hyperKey "F18" ] (_: {
              held = [
                hyperKey
                "Ctrl_R"
              ];
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
              "${hyper}-h" = "left";
              "${hyper}-j" = "down";
              "${hyper}-k" = "up";
              "${hyper}-l" = "right";
              "${hyper}-semicolon" = "end"; # macOS Cmd+Right ≈ end of line
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
