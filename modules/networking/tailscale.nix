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
#
# On darwin, userspace still gives each fleet peer its bare name: /etc/hosts
# points it at a loopback address of its own, and a root daemon forwards the
# ports of what the peer advertises from there through `tailscale nc`. So
# `curl http://altair:7377` works as it would with MagicDNS, for those ports.
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

  # The ports behind each advertised service (modules/system/fleet.nix). ssh
  # is left out: its Host blocks below already go through `tailscale nc`, and
  # launchd holds this machine's own :22.
  servicePorts = {
    limi-hub = [ 7377 ];
    limi-host = [ 7377 ];
    ollama = [ 11434 ];
    metrics = [
      8428
      80
    ];
    dns = [ 3000 ];
  };
  peerPorts = lib.filterAttrs (_: ports: ports != [ ]) (
    lib.mapAttrs (
      _: peer: lib.unique (lib.concatMap (s: servicePorts.${s} or [ ]) peer.services)
    ) fleetPeers
  );
  # 127.0.100.0/24 stays clear of the 127.0.0.x aliases other tools add.
  peerAddress = lib.listToAttrs (
    lib.imap1 (i: name: lib.nameValuePair name "127.0.100.${toString i}") (lib.attrNames peerPorts)
  );
  hostsBegin = "# BEGIN nix-config tailnet names";
  hostsEnd = "# END nix-config tailnet names";

  # One job per peer: launchd kills the whole process group when the script
  # exits, so a dead listener restarts with its siblings instead of leaving
  # them holding the ports.
  peerForwarder =
    name: ports:
    let
      address = peerAddress.${name};
    in
    pkgs.writeShellScript "tailnet-${name}" ''
      /sbin/ifconfig lo0 alias ${address} up
      ${lib.concatMapStrings (port: ''
        ${pkgs.socat}/bin/socat TCP-LISTEN:${toString port},bind=${address},reuseaddr,fork "EXEC:${pkgs.tailscale}/bin/tailscale nc ${name} ${toString port}" &
      '') ports}
      wait -n
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
            # `command`, not ProgramArguments: nix-darwin then waits for
            # /nix/store, which launchd starts daemons before it is mounted. A
            # daemon whose binary is missing at boot is never retried.
            launchd.daemons.tailscaled.command = lib.escapeShellArgs (
              [
                "${pkgs.tailscale}/bin/tailscaled"
                "--tun=userspace-networking"
                "--statedir=/var/lib/tailscale"
              ]
              ++ proxyFlags
            );
            launchd.daemons.tailscaled.serviceConfig = {
              RunAtLoad = true;
              KeepAlive = true;
              StandardErrorPath = "/var/log/tailscaled.log";
            };
          })
          (lib.mkIf userspace {
            launchd.daemons = lib.mapAttrs' (
              name: ports:
              lib.nameValuePair "tailnet-${name}" {
                command = "${peerForwarder name ports}";
                serviceConfig = {
                  RunAtLoad = true;
                  KeepAlive = true;
                  StandardErrorPath = "/var/log/tailnet-${name}.log";
                };
              }
            ) peerPorts;
          })
          {
            # macOS owns /etc/hosts and other tools write to it, so only this
            # block is ours. It goes away when userspace is off.
            system.activationScripts.postActivation.text = ''
              /usr/bin/sed -i "" '/^${hostsBegin}$/,/^${hostsEnd}$/d' /etc/hosts
              ${lib.optionalString userspace ''
                /usr/bin/printf '%s\n' ${
                  lib.escapeShellArgs (
                    [ hostsBegin ]
                    ++ lib.mapAttrsToList (name: address: "${address} ${name}") peerAddress
                    ++ [ hostsEnd ]
                  )
                } >> /etc/hosts
              ''}
              /usr/bin/dscacheutil -flushcache
              /usr/bin/killall -HUP mDNSResponder || true
            '';
          }
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
