{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixpkgs-unstable";
    };

    # NixOS hosts track nixos-unstable instead: it's gated on NixOS
    # integration tests and fully Hydra-cached for NixOS closures, which
    # nixpkgs-unstable (the darwin-friendly branch above) is not. Inputs are
    # fetched lazily per evaluated output, so each machine only ever
    # downloads its own branch.
    nixpkgs-nixos = {
      url = "github:nixos/nixpkgs/nixos-unstable";
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

    # Declarative disk partitioning for the NixOS host (polaris). The disko
    # config lives in the host module; the device is chosen at install time
    # via `disko-install --disk`.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # VS Code Marketplace + Open VSX extensions as Nix packages. nixpkgs only
    # ships a few hundred extensions; this exposes the full marketplace so the
    # vscode module can declare extensions like oxc, supermaven, etc.
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    opencode = {
      url = "github:anomalyco/opencode?rev=ddc30cd1516febc3a7d9d038ce65a51ab454c6e7";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hermes-agent = {
      url = "github:nousresearch/hermes-agent/v2026.5.29.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Runtime OAuth bypass patch for hermes-agent — lets Hermes use a
    # Claude Code Max/Pro subscription instead of pay-per-token credits.
    # Source-only (flake = false); wired into hermes via PYTHONPATH in
    # modules/dev/hermes/hermes.nix.
    hermes-claude-auth = {
      url = "github:kristianvast/hermes-claude-auth";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, utils, ... }@inputs:
    let
      mkDarwinHost = import ./lib/mkDarwinHost.nix { inherit inputs; };
      mkNixOSHost = import ./lib/mkNixOSHost.nix { inherit inputs; };
    in
    {
      darwinConfigurations = {
        m1 = import ./modules/hosts/m1.nix { inherit mkDarwinHost; };
      };

      nixosConfigurations = {
        polaris = import ./modules/hosts/polaris.nix { inherit mkNixOSHost; };
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
