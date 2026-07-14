# polaris disk layout — disko-managed, LUKS full-disk encryption → btrfs.
#
# The device is a placeholder: install day overrides it with
#   disko-install --disk main /dev/disk/by-id/<real-disk>
# so this file never needs editing for hardware changes.
#
# No swap partition by design: zram covers daily memory pressure, and
# future hibernation uses a resizable btrfs swapfile (see plan) — sized
# to whatever RAM the machine has at that point.
#
# Subvolume layout keeps snapshots cheap to add later (snapper/btrbk
# operate per-subvolume) without configuring any snapshot tooling now.
{ inputs, ... }:
{
  imports = [ inputs.disko.nixosModules.disko ];

  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/PLACEHOLDER";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          type = "EF00";
          size = "1G";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            settings.allowDiscards = true;
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@" = {
                  mountpoint = "/";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };

  zramSwap.enable = true;
}
