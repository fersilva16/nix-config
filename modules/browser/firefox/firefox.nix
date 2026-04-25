{
  mkUserModule,
  lib,
  pkgs,
  ...
}:
mkUserModule {
  name = "firefox";

  system.homebrew.casks = [ "firefox" ];

  parts = {
    profileApps = import ./profile-apps.nix { inherit lib pkgs; };
  };
}
