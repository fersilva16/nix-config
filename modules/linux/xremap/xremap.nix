# xremap — evdev key remapper with niri-aware per-app rules.
#
# This file owns only the daemon. Each part ships its own config file and
# the service merges every ~/.config/xremap/*.yml at start (xremap merges
# modmap/keymap/virtual_modifiers across files, and an exact-modifier match
# always beats an inexact one, so files don't fight over ordering). A rebuild
# only swaps the config symlinks, not the unit, so `--watch=config` is what
# reloads them:
#   - hyper (./hyper.nix): Caps Lock hyper layer.
#   - mac (./mac.nix): macOS Cmd/Opt semantics, per app.
#
# Bound to graphical-session.target: the session niri imports NIRI_SOCKET
# into systemd before it reaches that target, so xremap starts with the live
# socket (no login race, xremap/xremap#782) and restarts with the session. A
# nested niri never imports, so it can't leave xremap on a dead socket —
# which would hide the focused app and apply GUI rules in ghostty.
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
  home.systemd.user.services.xremap = {
    Unit = {
      Description = "xremap key remapper";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.runtimeShell} -c 'exec ${xremap}/bin/xremap --watch=device,config --allow-launch true %h/.config/xremap/*.yml'";
      Restart = "always";
      RestartSec = 1;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
