{ mkSystemModule, pkgs, ... }:
mkSystemModule {
  name = "nix";
  config.nix = {
    package = pkgs.nixVersions.latest;

    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };
}
