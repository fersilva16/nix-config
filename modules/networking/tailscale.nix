# Joining is a one-time manual `tailscale up` per host — no auth key lives in
# the repo. Without `userspace`, darwin runs the cask (its GUI owns the
# menu-bar state and the system extension) and linux runs the nixpkgs daemon.
#
# `userspace` runs tailscaled with no TUN interface, for hosts where another
# VPN fights it: on vega, the cask's network extension and Cloudflare WARP's
# both claim routes and DNS, and each drops the other's traffic. Userspace
# mode adds no interface, route or resolver, so the tailnet is reached only
# through tailscaled itself: ssh via `tailscale nc`, anything else via the
# SOCKS5/HTTP proxy on localhost:1055. Inbound tailnet connections land on
# this machine's localhost ports.
{
  mkUserModule,
  forPlatform,
  lib,
  pkgs,
  fleetPeers,
  ...
}:
let
  sshPeers = lib.filterAttrs (_: peer: lib.elem "ssh" peer.services) fleetPeers;

  proxyFlags = [
    "--socks5-server=localhost:1055"
    "--outbound-http-proxy-listen=localhost:1055"
  ];

  # Same nc as the ssh module: macOS lets only Apple's onto the LAN.
  nc = forPlatform {
    darwin = "/usr/bin/nc";
    linux = "${pkgs.netcat}/bin/nc";
  };

  # The ssh module swaps in <name>.local on the home LAN; that leg skips the
  # tailnet so it still works with tailscaled down.
  sshProxy = pkgs.writeShellScript "ssh-tailnet-proxy" ''
    case "$1" in
      *.local) exec ${nc} "$1" "$2" ;;
      *) exec ${pkgs.tailscale}/bin/tailscale nc "$1" "$2" ;;
    esac
  '';
in
mkUserModule {
  name = "tailscale";

  extraOptions.userspace = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Run tailscaled without a TUN interface; reach the tailnet through ssh and a localhost proxy.";
  };

  system =
    { enabledUsers }:
    let
      userspace = lib.any (u: u.tailscale.userspace) (lib.attrValues enabledUsers);
    in
    lib.mkMerge [
      (forPlatform {
        linux.services.tailscale = {
          enable = true;
          interfaceName = lib.mkIf userspace "userspace-networking";
          extraDaemonFlags = lib.mkIf userspace proxyFlags;
        };
        darwin = lib.mkMerge [
          (lib.mkIf userspace {
            environment.systemPackages = [ pkgs.tailscale ];
            launchd.daemons.tailscaled.serviceConfig = {
              ProgramArguments = [
                "${pkgs.tailscale}/bin/tailscaled"
                "--tun=userspace-networking"
                "--statedir=/var/lib/tailscale"
              ]
              ++ proxyFlags;
              RunAtLoad = true;
              KeepAlive = true;
              StandardErrorPath = "/var/log/tailscaled.log";
            };
          })
          (lib.mkIf (!userspace) { homebrew.casks = [ "tailscale-app" ]; })
        ];
      })
      (lib.mkIf userspace {
        programs.ssh.extraConfig = lib.concatStrings (
          lib.mapAttrsToList (name: _: ''

            Host ${name}
              ProxyCommand ${sshProxy} %h %p
          '') sshPeers
        );
      })
    ];
}
