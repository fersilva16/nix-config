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

    # Boot loader; hardware config generated at install time will join this
    # list as polaris-hardware.nix (nixos-generate-config --show-hardware-config).
    {
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
    }
  ];
}
