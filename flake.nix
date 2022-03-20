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

  outputs = { self, nixpkgs, nur, home-manager, utils, ... }@inputs:
    let
      overlays = [
        nur.overlay
      ];

      lib = import ./lib { inherit inputs overlays; };
    in
      {
        nixosConfigurations = {
          g3 = lib.makeHost {
            hostname = "g3";
            users = [ "fernando" ];
          };
        };

        homeConfigurations = {
          "fernando@g3" = lib.makeHome {
            username = "fernando";
            hostname = "g3";
          };
        };
      } // utils.lib.eachDefaultSystem (system:
        let
          pkgs = import nixpkgs { inherit system overlays; };
        in
        {
          packages = pkgs;

          devShell = pkgs.mkShell {
            buildInputs = with pkgs; [ nixfmt rnix-lsp home-manager git ];
          };
        });
}
