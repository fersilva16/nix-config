# incus — system containers and VMs (linux only).
#
# Standalone on purpose: tools that run throwaway containers (limi-box, for
# one) need it on the host, but incus itself needs nothing from them.
#
# The preseed sets up the defaults once and is re-applied on every boot
# (it never removes anything created by hand):
#
#   incusbr0       bridge, IPv4 NAT out of the host, no IPv6
#   default pool   btrfs, a subvolume under /var/lib/incus on the root
#                  btrfs (polaris-disk.nix), so instances are cheap
#                  snapshots instead of a dir copy or a loop file
#   default        profile: eth0 on incusbr0, root disk on that pool
#
# The incus module refuses the iptables firewall, so this switches the host
# to the nftables backend. incusbr0 is trusted: instances need DHCP and DNS
# from the host's dnsmasq on it.
{
  mkUserModule,
  forPlatform,
  ...
}:
let
  bridge = "incusbr0";
in
mkUserModule {
  name = "incus";

  system = forPlatform {
    linux = {
      virtualisation.incus = {
        enable = true;
        preseed = {
          networks = [
            {
              name = bridge;
              type = "bridge";
              config = {
                "ipv4.address" = "auto";
                "ipv4.nat" = "true";
                "ipv6.address" = "none";
              };
            }
          ];
          storage_pools = [
            {
              name = "default";
              driver = "btrfs";
              config.source = "/var/lib/incus/storage-pools/default";
            }
          ];
          profiles = [
            {
              name = "default";
              devices = {
                eth0 = {
                  name = "eth0";
                  network = bridge;
                  type = "nic";
                };
                root = {
                  path = "/";
                  pool = "default";
                  type = "disk";
                };
              };
            }
          ];
        };
      };

      networking = {
        nftables.enable = true;
        firewall.trustedInterfaces = [ bridge ];
      };
    };
  };

  user = forPlatform { linux.extraGroups = [ "incus-admin" ]; };
}
