# polaris disk layout — disko-managed, LUKS full-disk encryption → btrfs.
#
# The device is the real by-id path (stable across reboots/slots): every
# rebuild derives the initrd LUKS device from it, so a placeholder here
# would produce unbootable generations. NixOS lives on the Samsung 980
# Pro; the Windows disk (Kingston) is never referenced.
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
    device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_1TB_S5P2NL0W513531M";
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
            settings = {
              allowDiscards = true;
              # TPM2 auto-unlock (all input is bluetooth — unusable at the
              # LUKS prompt). Key enrolled once via:
              #   sudo systemd-cryptenroll --tpm2-device=auto <luks-part>
              # Passphrase stays enrolled as fallback. Disk remains
              # encrypted at rest (threat model: resale/RMA protection).
              crypttabExtraOpts = [ "tpm2-device=auto" ];
            };
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
