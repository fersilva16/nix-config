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
      inputs.brew-src.follows = "brew-src";
    };

    # Pin brew to a version that includes the cask OS-dependency regression fix
    # (https://github.com/Homebrew/brew/pull/22261), required for casks like
    # stremio and iina that combine `on_arm`/`on_intel` macOS deps with a
    # top-level `depends_on :macos`.
    brew-src = {
      url = "github:Homebrew/brew/5.1.13";
      flake = false;
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
      url = "github:anomalyco/opencode?rev=7fe7b9f258e36ad9f9acded20c5a9df201da19d5";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, utils, ... }@inputs:
    let
      mkDarwinHost = import ./lib/mkDarwinHost.nix { inherit inputs; };
    in
    {
      darwinConfigurations = {
        m1 = import ./modules/hosts/m1.nix { inherit mkDarwinHost; };
      };
    }
    // utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages = pkgs;

        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixd
            statix
            nixfmt

            shellcheck

            prettier

            pre-commit
          ];

          shellHook = ''
            pre-commit install -f
          '';
        };
      }
    );
}
