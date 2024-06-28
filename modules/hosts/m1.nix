_:
{
  networking.hostName = "m1";

  imports = [
    ../users/m1-fernando.nix

    ../darwin/sudo-touchid.nix
    ../fonts/caskaydia-cove.nix
    ../utils/nix.nix
    ../utils/pkg-config.nix
  ];
}
