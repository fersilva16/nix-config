# wake-on-lan — wake a sleeping fleet peer from another machine on the LAN.
#
# A host that sets `mac` keeps its WiFi listening for a magic packet while
# suspended and advertises that MAC to the fleet (modules/system/fleet.nix).
# Every host gets `wake <peer>` for the peers that advertise one.
#
# WiFi only (polaris: RTL8922AE), so this wakes from suspend, never from
# power-off: wake-on-WLAN needs the card associated, and a powered-off card
# is not. NetworkManager arms it on the phy each time a connection comes up;
# 8 is its magic-packet flag (NM_SETTING_WIRELESS_WAKE_ON_WLAN_MAGIC). The
# board must also keep the card powered in sleep: ErP off, wake by PCI-E on.
#
# The packet is a LAN broadcast, so the sender has to be on the home LAN;
# it does not cross the tailnet.
{
  mkSystemModule,
  forPlatform,
  fleetPeers,
  lib,
  pkgs,
  ...
}:
let
  wakeable = lib.filterAttrs (_: peer: peer ? wakeOnLan) fleetPeers;

  wake = pkgs.writeShellApplication {
    name = "wake";
    runtimeInputs = [ pkgs.wakeonlan ];
    text = ''
      case "''${1:-}" in
      ${lib.concatStrings (
        lib.mapAttrsToList (name: peer: ''
          ${name}) wakeonlan ${peer.wakeOnLan} ;;
        '') wakeable
      )}
        *)
          echo "usage: wake ${lib.concatStringsSep "|" (lib.attrNames wakeable)}" >&2
          exit 1
          ;;
      esac
    '';
  };
in
mkSystemModule {
  name = "wake-on-lan";

  extraOptions = {
    mac = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "This host's WiFi MAC; set it to make the host wakeable over the LAN.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = wake;
      description = "The `wake <peer>` command, for services that wake a peer before reaching it.";
    };
  };

  config =
    { cfg, ... }:
    lib.mkMerge [
      { environment.systemPackages = lib.optional (wakeable != { }) wake; }
      (lib.mkIf (cfg.mac != null) (
        {
          fleet.wakeOnLan = cfg.mac;
        }
        // forPlatform {
          linux.networking.networkmanager.settings.connection."wifi.wake-on-wlan" = 8;
        }
      ))
    ];
}
