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

    # Host specifics; hardware config generated at install time will join
    # this list as polaris-hardware.nix (nixos-generate-config).
    {
      # Windows (separate disk) keeps the RTC in localtime; adjusting here
      # avoids registry surgery on the Windows side.
      time.hardwareClockInLocalTime = true;
    }
  ];
}
