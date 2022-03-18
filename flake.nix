{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nur.url = "github:nix-community/NUR";

    utils.url = "github:numtide/flake-utils";

    hardware = {
      url = "github:nixos/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nur, home-manager, ... }@inputs:
    let
      overlays = [
        nur.overlay
      ];

      system = "x86_64-linux";
      hostname = "g3";
    in
      {
        inherit overlays;

        nixosConfigurations = {
          g3 = nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = {
              inherit inputs system hostname;
            };

            modules = [
              ./hosts/g3.nix
              ./users/fernando/system.nix
            ];
          };
        };

        homeConfigurations = {
          "fernando@g3" = home-manager.lib.homeManagerConfiguration {
            inherit system;

            username = "fernando";
            homeDirectory = "/home/fernando";

            configuration = ./users/fernando/home.nix;

            extraModules = [
              {
                nixpkgs = {
                  inherit overlays;
                  config.allowUnfree = true;
                };
              }
            ];

            extraSpecialArgs = {
              inherit inputs system hostname;
            };
          };
        };
      };
}
