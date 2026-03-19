_: {
  networking.hostName = "m1";

  imports = [
    ../users/m1-fernando.nix

    ../darwin/darwin-default.nix
    ../darwin/sudo-touchid.nix
    ../darwin/watcher.nix
    ../fonts/caskaydia-cove.nix
    ../system/nix.nix
    ../system/pkg-config.nix
    ../system/sshd.nix
    ../cli/wget.nix
    ../cli/unrar.nix
  ];
}
