{ inputs, overlays }:
let
  inherit (inputs) nixpkgs home-manager;
in
{ hostname, system, users }:
nixpkgs.lib.nixosSystem {
  inherit system;

  specialArgs = {
    inherit inputs system hostname;
  };

  modules = [
    home-manager.nixosModule

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
