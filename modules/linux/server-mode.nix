# server-mode — park the machine as a headless box.
#
# The idle cost worth cutting is the desktop session itself: niri plus the
# noctalia shell keep the 5070 Ti out of its deep idle states and hold the
# monitor awake. sshd and tailscale live in multi-user.target, so stopping
# the display manager never touches remote access.
#
# `display-manager.service` rather than `greetd.service`: that alias is set
# by the greetd module itself, so this keeps working if the greeter is ever
# swapped.
#
# Deliberately NOT `systemctl isolate multi-user.target` — isolate is not
# guaranteed to spare the SSH session that issued it, and it frees the same
# watts. Needs root, so it is `sudo server-mode on` over SSH.
{ mkSystemModule, pkgs, ... }:
let
  server-mode = pkgs.writeShellApplication {
    name = "server-mode";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      case "''${1:-status}" in
        on)
          systemctl stop display-manager.service
          echo "server mode on — desktop stopped"
          ;;
        off)
          systemctl start display-manager.service
          echo "server mode off — desktop started"
          ;;
        status)
          if systemctl is-active --quiet display-manager.service; then
            echo "off — desktop running"
          else
            echo "on — headless"
          fi
          ;;
        *)
          echo "usage: server-mode on|off|status" >&2
          exit 1
          ;;
      esac
    '';
  };
in
mkSystemModule {
  name = "server-mode";
  config = {
    environment.systemPackages = [ server-mode ];

    # Blank the text console after a minute so the monitor reaches DPMS off
    # once the session is down. Only affects the VT — a Wayland session owns
    # the display otherwise, so normal desktop use is unchanged.
    boot.kernelParams = [ "consoleblank=60" ];
  };
}
