# Declarative BIOS settings through the kernel's firmware-attributes class
# (think-lmi on Lenovo, dell-wmi-sysman, hp-bioscfg). Hosts list settings by
# their attribute name, e.g. "After Power Loss" = "Power On"; the names and
# allowed values are in /sys/class/firmware-attributes/*/attributes/<name>/
# (current_value needs root, possible_values does not).
#
# A oneshot at boot, and on every switch that changes the list, writes only
# the settings that differ: Lenovo firmware accepts about 48 saves before it
# refuses more until someone enters the BIOS setup, so never rewrite settings
# that are already right. Changes take effect on the next reboot.
#
# Not supported: a BIOS admin password. With one set, every write is refused
# and the unit fails.
{
  mkSystemModule,
  lib,
  pkgs,
  ...
}:
mkSystemModule {
  name = "bios";

  extraOptions.settings = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example = {
      "After Power Loss" = "Power On";
    };
    description = "BIOS settings to enforce, keyed by firmware-attributes name.";
  };

  config =
    { cfg, ... }:
    let
      bios-settings = pkgs.writeShellApplication {
        name = "bios-settings";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.systemd
        ];
        text = ''
          # think-lmi is loaded by udev on its WMI device; wait for coldplug.
          udevadm settle --timeout=30 || true

          failed=0
          apply() {
            local name=$1 want=$2 attr have
            attr=$(printf '%s\n' /sys/class/firmware-attributes/*/attributes/"$name" | head -n 1)
            if [ ! -d "$attr" ]; then
              echo "no such BIOS setting: $name" >&2
              failed=1
              return
            fi
            have=$(<"$attr/current_value")
            [ "$have" = "$want" ] && return
            if printf '%s' "$want" >"$attr/current_value"; then
              echo "$name: $have -> $want (applies on next reboot)"
            else
              echo "failed to set $name to $want (allowed: $(<"$attr/possible_values"))" >&2
              failed=1
            fi
          }

          ${lib.concatStrings (
            lib.mapAttrsToList (
              name: value: "apply ${lib.escapeShellArg name} ${lib.escapeShellArg value}\n"
            ) cfg.settings
          )}
          exit "$failed"
        '';
      };
    in
    lib.mkIf (cfg.settings != { }) {
      systemd.services.bios-settings = {
        description = "Apply declarative BIOS settings";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-udev-trigger.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = lib.getExe bios-settings;
        };
      };
    };
}
