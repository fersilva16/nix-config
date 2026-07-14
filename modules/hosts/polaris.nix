{ mkNixOSHost }:
let
  fernando = import ../users/polaris-fernando.nix;
in
mkNixOSHost {
  hostName = "polaris";
  primaryUser = fernando;
  users = [ fernando ];

  extraModules = [
    # Placeholder hardware/disk config so the toplevel evaluates before the
    # machine exists. Replaced in Phase 1 (disko layout) and at install time
    # (nixos-generate-config → polaris-hardware.nix).
    {
      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "btrfs";
      };
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
    }
  ];
}
