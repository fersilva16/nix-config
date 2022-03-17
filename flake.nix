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

  outputs = { self, nixpkgs, nur, home-manager, ... }@inputs:
    let
      overlays = [
        self.overlay
        nur.overlay
      ];
      system = "x86_64-linux";
      hostname = "g3";
    in
      {
        nixosConfigurations = {
          g3 = nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = { inherit inputs system hostname; };
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
