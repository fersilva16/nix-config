{ mkNixOSHost }:
let
  fernando = import ../users/polaris-fernando.nix;
in
mkNixOSHost {
  hostName = "polaris";
  primaryUser = fernando;
  users = [ fernando ];

  extraModules = [
    ./polaris-disk.nix

    # Host specifics; hardware config is generated at install time
    # (nixos-generate-config) and picked up when present — pathExists is
    # false while the file is missing/untracked, so eval works either way.
  ]
  ++ (if builtins.pathExists ./polaris-hardware.nix then [ ./polaris-hardware.nix ] else [ ])
  ++ [
    {
      # Windows (separate disk) keeps the RTC in localtime; adjusting here
      # avoids registry surgery on the Windows side.
      time.hardwareClockInLocalTime = true;

      # Windows ESP lives on the other disk, so systemd-boot cannot
      # auto-detect it. Device handle discovered via the edk2 UEFI shell
      # (`map -c`, the FS whose \EFI contains Microsoft).
      boot.loader.systemd-boot.windows."11".efiDeviceHandle = "HD0b";
    }
  ];
}
