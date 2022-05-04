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

    emacs-overlay.url = "github:nix-community/emacs-overlay";

    doom-emacs = {
      url = "github:nix-community/nix-doom-emacs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.emacs-overlay.follows = "emacs-overlay";
    };
  };

  outputs = { nixpkgs, utils, ... }@inputs:
    let
      overlay = import ./overlay/overlay.nix;

      overlays = with inputs; [
        overlay
        nur.overlay
        emacs-overlay.overlay
      ];

      mkHost = import ./lib/mkHost.nix { inherit inputs overlays; };
    in
    {
      inherit overlay overlays;

      nixosConfigurations = {
        g3 = mkHost {
          hostname = "g3";
          users = [ "fernando" ];
        };
      };
    } // utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system overlays; };

        ghcWithPackages = pkgs.ghc.withPackages (haskellPackages:
          with haskellPackages; [
            xmonad
            xmonad-extras
            xmonad-contrib

            hlint
            haskell-language-server
          ]);
      in
      {
        packages = pkgs;

        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            rnix-lsp
            statix
            nix-linter
            nixpkgs-fmt

            shellcheck

            nodePackages.prettier

            pre-commit

            ghcWithPackages
          ];

          shellHook = ''
            pre-commit install
          '';
        };

        devShells = import ./devShells/devShells.nix { inherit pkgs; };
      }
    );
}
