_: {
  networking.hostName = "m1";

  imports = [
    ../users/m1-fernando.nix

    # User modules (mkUserModule pattern — enabled per-user via modules.users.<name>)
    ../cli/bat.nix

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
