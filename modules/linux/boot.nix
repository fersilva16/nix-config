# systemd-boot for NixOS hosts — no GRUB.
#
# The edk2 UEFI shell entry exists to discover the Windows ESP device
# handle for dual-boot chainloading (Windows lives on a separate disk, so
# systemd-boot cannot auto-detect it). The windows entry itself is added
# per-host once the handle is known (see .omo/plans/nixos-second-host.md).
{ mkSystemModule, ... }:
mkSystemModule {
  name = "boot";
  config.boot = {
    loader = {
      systemd-boot = {
        enable = true;
        consoleMode = "max";
        editor = false;
        configurationLimit = 20;
        edk2-uefi-shell.enable = true;
      };
      efi.canTouchEfiVariables = true;
      timeout = 5;
    };

    # systemd stage-1: required for TPM2 LUKS auto-unlock
    # (systemd-cryptenroll), and the modern initrd generally.
    initrd.systemd.enable = true;
  };
}
