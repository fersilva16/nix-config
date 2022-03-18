{ modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd = {
    availableKernelModules = [ "ata_piix" "ohci_pci" "sd_mod" "sr_mod" ];
    kernelModules = [  ];

    luks.devices."lvm" = {
      device = "/dev/sda1";
      preLVM = true;
      allowDiscards = true;
    };
  };

  boot.resumeDevice = "/swapfile";
  swapDevices = [
    {
      device = "/swapfile";
      size = 6144;
    }
  ];

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/lvm";
      fsType = "btrfs";
      options = [ "subvol=root" ];
    };

    "/home" = {
      device = "/dev/disk/by-label/lvm";
      fsType = "btrfs";
      options = [ "subvol=home" ];
    };

    "/boot" = {
      device = "/dev/disk/by-label/boot";
      fsType = "vfat";
    };
  };
}
