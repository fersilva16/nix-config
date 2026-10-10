# The fleet: every machine this flake manages, keyed by hostname. flake.nix
# splits it into darwinConfigurations / nixosConfigurations by class, and
# mkDarwinHost / mkNixOSHost hand each host the others as the `fleetPeers`
# module argument: fleetPeers.<name> is that machine's own `fleet` option
# (modules/system/fleet.nix), what it advertises about itself. A new machine
# is one line here.
#
# Peers are read lazily: nothing about polaris is evaluated on vega until a
# module that uses `fleetPeers` is built, and then only as far as polaris's
# `fleet` option needs.
#
# The key must equal the host's hostName, and every address derives from it:
#   <name>        MagicDNS on the tailnet, reachable from anywhere
#   <name>.local  mDNS on the home LAN (avahi on linux, Bonjour on darwin)
# If MagicDNS is ever off, polaris's tailnet address is 100.123.15.108.
{ mkDarwinHost, mkNixOSHost }:
{
  vega = import ./vega.nix { inherit mkDarwinHost; };
  polaris = import ./polaris.nix { inherit mkNixOSHost; };
}
