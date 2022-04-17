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

  outputs = { self, nixpkgs, utils, ... }@inputs:
    let
      overlay = import ./overlays/overlays.nix;

      overlays = with inputs; [ overlay nur.overlay emacs-overlay.overlay ];

      lib = import ./lib/lib.nix { inherit inputs overlays; };
    in
    {
      inherit overlay overlays;

      nixosConfigurations = {
        g3 = lib.makeHost {
          hostname = "g3";
          users = [ "fernando" ];
        };
      };
    } // utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system overlays; };

        ghcWithPackages = pkgs.ghc.withPackages (haskellPackages:
          with haskellPackages; [
            haskell-language-server
            xmonad
            xmonad-extras
            xmonad-contrib
          ]);
      in
      {
        packages = pkgs;

        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixfmt
            rnix-lsp
            home-manager
            git
            ghcWithPackages
          ];
        };

        devShells = import ./devShells/devShells.nix { inherit pkgs; };
      }
    );
}
