{ modulesPath, inputs, lib, config, ... }:
let
  inherit (inputs.hardware.nixosModules) dell-g3-3779;

  fsDefaultOptions =
    [
      "compress=lzo"
      "noatime"
      "discard"
      "ssd"
      "autodefrag"
      "space_cache"
    ];
in
{
  imports = [
    dell-g3-3779

    ./common/audio.nix
    ./common/bluetooth.nix
    ./common/boot.nix
    ./common/cachix.nix
    ./common/common.nix
    ./common/console.nix
    ./common/docker.nix
    ./common/fingerprint.nix
    ./common/fonts.nix
    ./common/gcc.nix
    ./common/gnupg.nix
    ./common/i18n.nix
    ./common/kernel.nix
    ./common/light.nix
    ./common/monitors.nix
    ./common/networking.nix
    ./common/nix.nix
    ./common/nvidia.nix
    ./common/opengl.nix
    ./common/sensors.nix
    ./common/ssh.nix
    ./common/time.nix
    ./common/utils.nix
    ./common/xserver.nix
    ./common/zip.nix

    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.kernelModules = [ "kvm-intel" ];
  boot.kernelParams = [ "resume=/var/swapfile" "resume_offset=16400" ];

  boot.initrd = {
    availableKernelModules = [
      "xhci_pci"
      "ahci"
      "nvme"
      "usb_storage"
      "usbhid"
      "sd_mod"
    ];

    kernelModules = [ ];
    supportedFilesystems = [ "btrfs" ];

    luks.devices."lvm" = {
      device = "/dev/nvme0n1p6";
      preLVM = true;
      allowDiscards = true;
    };
  };

  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";
  hardware.cpu.intel.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;

  boot.resumeDevice = "/dev/disk/by-label/root";
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
