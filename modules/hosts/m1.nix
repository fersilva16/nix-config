_:
{
  networking.hostName = "m1";

  imports = [
    ../users/m1-fernando.nix

    ../darwin/darwin-default.nix
    ../darwin/sudo-touchid.nix
    ../darwin/watcher.nix
    ../fonts/caskaydia-cove.nix
    ../utils/nix.nix
    ../utils/pkg-config.nix
    ../cli/wget.nix
    ../cli/unrar.nix
  ];
}
