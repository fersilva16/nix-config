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
    }
  ];
}
