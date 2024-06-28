{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixpkgs-unstable";
    };

    utils.url = "github:numtide/flake-utils";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew = {
      url = "github:zhaofengli/nix-homebrew";
    };

    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };

    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
  };

  outputs = { nixpkgs, utils, ... }@inputs:
    let
      overlay = import ./overlay/overlay.nix;

      overlays = with inputs; [
        overlay
        # nur.overlay
        # emacs-overlay.overlay
      ];

      mkDarwinHost = import ./lib/mkDarwinHost.nix { inherit inputs overlays; };
    in
    {
      inherit overlay overlays;

      darwinConfigurations = {
        m1 = mkDarwinHost {
          hostname = "m1";
          system = "aarch64-darwin";
          users = [ "fernando-m1" ];
        };
      };
    } // utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system overlays; };
      in
      {
        packages = pkgs;

        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            rnix-lsp
            statix
            nixpkgs-fmt

            shellcheck

            nodePackages.prettier

            pre-commit
          ];

          shellHook = ''
            pre-commit install
          '';
        };
      }
    );
}
