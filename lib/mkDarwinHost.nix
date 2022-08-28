{ inputs, overlays }:
let
  inherit (inputs) nixpkgs home-manager darwin;
in
{ hostname, system, users }:
darwin.lib.darwinSystem {
  inherit system;

  specialArgs = {
    inherit inputs system hostname;
  };

  modules = [
    home-manager.darwinModules.home-manager

    (../hosts + "/${hostname}.nix")
    {
      networking.hostName = hostname;

      nixpkgs = {
        inherit overlays;
        config.allowUnfree = true;
      };

      home-manager = {
        useGlobalPkgs = true;
      };
    }
  ] ++ nixpkgs.lib.forEach users (user: ../users + "/${user}.nix");
}
