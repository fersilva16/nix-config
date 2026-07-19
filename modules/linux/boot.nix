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
          };
          efi.canTouchEfiVariables = true;
          timeout = 5;
        };

        # systemd stage-1: required for TPM2 LUKS auto-unlock
        # (systemd-cryptenroll), and the modern initrd generally.
        initrd.systemd.enable = true;
      };

      environment.systemPackages = lib.optional (winVersions != [ ]) boot-windows;
    };
}
