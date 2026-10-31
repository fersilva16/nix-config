# altair disk layout — disko-managed, LUKS full-disk encryption → btrfs.
# Same shape as polaris-disk.nix, minus the hibernation swapfile (a server
# never hibernates).
#
# `device` is only read when disko formats the disk: the generated
# fileSystems and initrd LUKS device use /dev/disk/by-partlabel/disk-main-*,
# so rebuilds never depend on it. On the install USB, /dev/sda is the USB
# stick itself, never the target.
{ inputs, ... }:
{
  imports = [ inputs.disko.nixosModules.disko ];

  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";
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
              # Headless, so it must boot unattended: TPM2 auto-unlock. Key
              # enrolled once after install via:
              #   sudo systemd-cryptenroll --tpm2-device=auto /dev/disk/by-partlabel/disk-main-luks
              # The passphrase stays enrolled as fallback (needs a keyboard).
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

  # 8 GB RAM: zram absorbs memory pressure, no disk swap.
  zramSwap.enable = true;
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;
  };
}
