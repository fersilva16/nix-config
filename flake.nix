{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixpkgs-unstable";
      # url = "github:nixos/nixpkgs/nixos-unstable";
    };

    # nur.url = "github:nix-community/NUR";

    utils.url = "github:numtide/flake-utils";

    # hardware = {
    #   url = "github:nixos/nixos-hardware";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # emacs-overlay = {
    #   url = "github:nix-community/emacs-overlay";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.flake-utils.follows = "utils";
    # };

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

      mkHost = import ./lib/mkHost.nix { inherit inputs overlays; };
      mkDarwinHost = import ./lib/mkDarwinHost.nix { inherit inputs overlays; };
    in
    {
      inherit overlay overlays;

      # nixosConfigurations = {
      #   g3 = mkHost {
      #     hostname = "g3";
      #     system = "x86_64-linux";
      #     users = [ "fernando" ];
      #   };
      # };

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
