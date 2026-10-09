# xremap — evdev key remapper with niri-aware per-app rules.
#
# This file owns only the daemon. Each part ships its own config file and
# the service merges every ~/.config/xremap/*.yml at start (xremap merges
# modmap/keymap/virtual_modifiers across files, and an exact-modifier match
# always beats an inexact one, so files don't fight over ordering):
#   - hyper (./hyper.nix): Caps Lock hyper layer.
#   - mac (./mac.nix): macOS Cmd/Opt semantics, per app.
#
# Started by niri rather than a session target: niri imports NIRI_SOCKET
# first, which sidesteps xremap's login race (xremap/xremap#782).
{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  xremap = pkgs.xremap.niri;
  yaml = pkgs.formats.yaml { };
  # Shared with both parts: mac rules combine Cmd/Opt with hyper.
  hyperKey = "CapsLock";
in
mkUserModule {
  name = "xremap";
  parts = {
    hyper = import ./hyper.nix {
      inherit
        pkgs
        lib
        yaml
        hyperKey
        ;
    };
    mac = import ./mac.nix { inherit lib yaml hyperKey; };
  };
  # Unprivileged evdev input + uinput output (xremap runs as the user).
  system.hardware.uinput.enable = true;
  user.extraGroups = [
    "input"
    "uinput"
  ];
  home =
    { userCfg, ... }:
    {
      systemd.user.services.xremap = {
        Unit.Description = "xremap key remapper";
        Service = {
          ExecStart = "${pkgs.runtimeShell} -c 'exec ${xremap}/bin/xremap --watch=device --allow-launch true %h/.config/xremap/*.yml'";
          Restart = "always";
          RestartSec = 1;
        };
      };
      xdg.configFile."niri/config.kdl".text = lib.mkIf userCfg.niri.enable ''

        spawn-sh-at-startup "systemctl --user import-environment NIRI_SOCKET && systemctl --user restart xremap.service"
      '';
    };
}
