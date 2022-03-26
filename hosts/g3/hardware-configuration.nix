{ modulesPath, lib, config, ... }:
let
  fsDefaultOptions = [ "compress=lzo" "noatime" "discard" "ssd" "autodefrag" "space_cache" ];
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.kernelModules = [ "kvm-intel" ];

  boot.initrd = {
    availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "usbhid" "sd_mod" ];
    kernelModules = [  ];
    supportedFilesystems = [ "btrfs" ];

    luks.devices."lvm" = {
      device = "/dev/nvme0n1p2";
      preLVM = true;
      allowDiscards = true;
    };
  };

  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  boot.resumeDevice = "/var/swapfile";
  swapDevices = [
    {
      device = "/var/swapfile";
      size = 18432;
    }
  ];

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/root";
      fsType = "btrfs";
      options = [ "subvol=root" ] ++ fsDefaultOptions;
    };

    "/home" = {
      device = "/dev/disk/by-label/root";
      fsType = "btrfs";
      options = [ "subvol=home" "nosuid" ] ++ fsDefaultOptions;
    };

    "/nix" = {
      device = "/dev/disk/by-label/root";
      fsType = "btrfs";
      options = [ "subvol=nix" ] ++ fsDefaultOptions;
    };

    "/boot" = {
      device = "/dev/disk/by-label/boot";
      fsType = "vfat";
    };
  };
}
