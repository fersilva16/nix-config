{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
mkUserModule {
  name = "slack";
  casks = [ "slack" ];

  parts = {
    # Explicit opt-in: reads only the dedicated Chrome profile, using Chrome
    # Safe Storage from the login keychain to decrypt its cookies.
    later = import ./later.nix { inherit pkgs lib; };
  };
}
