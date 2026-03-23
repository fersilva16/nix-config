{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixpkgs-unstable";
    };

    utils = {
      url = "github:numtide/flake-utils";
    };

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
      inputs.nixpkgs.follows = "nixpkgs";
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

    homebrew-schpet-tap = {
      url = "github:schpet/homebrew-tap";
      flake = false;
    };

    direnv-instant = {
      url = "github:Mic92/direnv-instant";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    opencode = {
      url = "github:anomalyco/opencode/production";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    bun2nix = {
      url = "github:nix-community/bun2nix?tag=2.0.8";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, utils, ... }@inputs:
    let
      overlay = import ./overlay/overlay.nix;

      overlays = [
        inputs.bun2nix.overlays.default
        overlay
      ];

      mkDarwinHost = import ./lib/mkDarwinHost.nix { inherit inputs overlays; };
    in
    {
      inherit overlay overlays;

      darwinConfigurations = {
        m1 = mkDarwinHost ./modules/hosts/m1.nix;
      };
    }
    // utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system overlays; };
      in
      {
        packages = pkgs;

        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixd
            statix
            nixfmt-rfc-style

            shellcheck

            nodePackages.prettier

            pre-commit
          ];

          shellHook = ''
            pre-commit install -f
          '';
        };
      }
    );
}
