{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nur.url = "github:nix-community/NUR";

    hardware = {
      url = "github:nixos/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      overlays = [
        self.overlay
        nur.overlay
      ];
    in
      {
        nixosConfigurations = {
          g3 = nixpkgs.lib.nixosSystem {
            modules = [
              ./hosts/g3.nix
              { inherit overlays; }
              ./users/fernando/system.nix
            ];
          };
        };

        homeConfigurations = {
          "fernando@g3" = home-manager.lib.homeManagerConfiguration {
            username = "fernando";
            homeDirectory = "/home/fernando";

            configuration = ./users/fernando/home.nix;

            extraModules = [
              { inherit overlays; }
            ];

            extraSpecialArgs = {
              inherit inputs;
            };
          };
        };
      };
}
