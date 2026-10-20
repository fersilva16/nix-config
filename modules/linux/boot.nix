# systemd-boot for NixOS hosts — no GRUB.
#
# The edk2 UEFI shell entry exists to discover the Windows ESP device
# handle for dual-boot chainloading (Windows lives on a separate disk, so
# systemd-boot cannot auto-detect it). The windows entry itself is added
# per-host once the handle is known (see .omo/plans/nixos-second-host.md).
{
  mkSystemModule,
  pkgs,
  lib,
  ...
}:
mkSystemModule {
  name = "boot";
  config =
    { config, ... }:
    let
      # systemd-boot names Windows entries windows_<version>.conf (from the
      # windows.<version> option set per-host in polaris.nix). `boot-windows`
      # reboots straight into it via logind's one-shot boot-entry override —
      # a native systemd feature, no chainloading dance needed.
      # ponytail: takes the first configured entry; add a picker if a second
      # Windows install ever shows up.
      winVersions = builtins.attrNames config.boot.loader.systemd-boot.windows;
      boot-windows = pkgs.writeShellScriptBin "boot-windows" ''
        exec systemctl reboot --boot-loader-entry=windows_${lib.head winVersions}.conf
      '';
    in
    {
      boot = {
        loader = {
          systemd-boot = {
            enable = true;
            consoleMode = "max";
            editor = false;
            configurationLimit = 20;
            edk2-uefi-shell.enable = true;
            # Offline RAM test, no USB stick needed. Reach it with
            # `systemctl reboot --boot-loader-entry=memtest86.conf`.
            # Hand-rolled instead of `memtest86.enable` (same file and entry
            # name) because that option cannot pass boot options:
            # nobigstatus keeps the PASS/FAIL banner from covering the error
            # details, which matters when the keyboard does not work in
            # memtest to dismiss it; usbinit=3 is its USB keyboard workaround.
            extraFiles."efi/memtest86/memtest.efi" = pkgs.memtest86plus.efi;
            extraEntries."memtest86.conf" = ''
              title Memtest86+
              efi /efi/memtest86/memtest.efi
              options nobigstatus usbinit=3
              sort-key o_memtest86
            '';
          };
          efi.canTouchEfiVariables = true;
          # Skip the menu; hold Space at boot to show it. `boot-windows`
          # covers the usual reason to pick an entry.
          timeout = 0;
        };

        # systemd stage-1: required for TPM2 LUKS auto-unlock
        # (systemd-cryptenroll), and the modern initrd generally.
        initrd.systemd.enable = true;
      };

      environment.systemPackages = lib.optional (winVersions != [ ]) boot-windows;
    };
}
