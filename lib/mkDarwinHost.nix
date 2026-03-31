{ inputs, overlays }:
let
  system = "aarch64-darwin";
  inherit (inputs)
    nixpkgs
    home-manager
    darwin
    nix-homebrew
    ;
in
host:
darwin.lib.darwinSystem {
  inherit system;

  specialArgs = {
    inherit inputs system;
    mkUserModule = import ./mkUserModule.nix;
    forPlatform = import ./forPlatform.nix system;
  };

  modules = [
    home-manager.darwinModules.home-manager
    nix-homebrew.darwinModules.nix-homebrew

    host
    {
      nixpkgs = {
        inherit overlays;
        config.allowUnfree = true;
      };

      home-manager = {
        useGlobalPkgs = true;
      };
    }
  ];
}
