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

    # Noctalia desktop shell for niri (polaris). Pinned to the stable v4
    # line (quickshell-based); main is the v5 native-rewrite beta. nixpkgs
    # deliberately not followed — keeping their lock maximizes hits on
    # noctalia.cachix.org (quickshell fork is expensive to build).
    noctalia = {
      url = "github:noctalia-dev/noctalia/legacy-v4";
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
      url = "github:anomalyco/opencode/v1.18.29";
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

    # First-party OpenClaw flake — upstream points Nix users here rather than
    # at the nixpkgs package. Ships the home-manager module that owns the
    # launchd gateway agent and renders ~/.openclaw/openclaw.json immutably.
    #
    # Deliberately NOT following our nixpkgs, and this is load-bearing: openclaw
    # refuses to start on node < 22.22.3, their pin carries nodejs_22 = 22.23.1
    # and ours carries 22.22.2. Building it against our nixpkgs yields a gateway
    # that exits 1 and crash-loops under launchd. Cost is a second nixpkgs in
    # the lock.
    nix-openclaw = {
      url = "github:openclaw/nix-openclaw";
    };
  };

  outputs =
    { nixpkgs, utils, ... }@inputs:
    let
      mkDarwinHost = import ./lib/mkDarwinHost.nix { inherit inputs; };
      mkNixOSHost = import ./lib/mkNixOSHost.nix { inherit inputs; };

      inherit (nixpkgs) lib;

      darwinConfigurations = {
        vega = import ./modules/hosts/vega.nix { inherit mkDarwinHost; };
      };

      nixosConfigurations = {
        polaris = import ./modules/hosts/polaris.nix { inherit mkNixOSHost; };
      };
    in
    {
      inherit darwinConfigurations nixosConfigurations;
    }
    // utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # The neovim config is Lua embedded in Nix strings, which Nix treats as
        # opaque text — a syntax error there survives a rebuild and only shows
        # up when nvim next starts. Byte-compile the generated init.lua so
        # `nix flake check` catches it first. LuaJIT, not lua5_1, because that
        # is what nvim actually runs (it accepts `goto`, 5.1 does not).
        #
        # ponytail: syntax only. A missing API key or absent binary still needs
        # a guard in the module itself — this check cannot see runtime paths.
        nvimInitCheck =
          hostName: hostCfg:
          pkgs.runCommand "nvim-init-lua-${hostName}" { } ''
            ${pkgs.luajit}/bin/luajit -b ${
              hostCfg.config.home-manager.users.fernando.xdg.configFile."nvim/init.lua".source
            } /dev/null && touch $out
          '';

        # Hammerspoon's init.lua has the widest blast radius of any Lua here: a
        # syntax error takes the Caps Lock → Hyper eventtap with it, so the fix
        # has to be typed on a keyboard whose Caps Lock no longer works. Nix
        # treats it as opaque text and Hammerspoon only complains in a log file,
        # which is exactly the combination that ships a broken one.
        hammerspoonInitCheck =
          hostName: hostCfg:
          pkgs.runCommand "hammerspoon-init-lua-${hostName}" { } ''
            ${pkgs.luajit}/bin/luajit -b ${
              hostCfg.config.home-manager.users.fernando.home.file.".hammerspoon/init.lua".source
            } /dev/null && touch $out
          '';

        # Same blind spot as the nvim check, one layer further: nix cannot see a
        # Lua error, AND Hammerspoon reports one only in a log nobody reads, so a
        # broken panel is a panel that silently never appears. This runs the
        # panel's own assertions against the INSTALLED file — prelude included —
        # so the generated config header is covered too.
        todoistPanelCheck =
          hostName: hostCfg:
          pkgs.runCommand "todoist-panel-lua-${hostName}" { } ''
            PANEL=${
              hostCfg.config.home-manager.users.fernando.home.file.".hammerspoon/extras/todoist-panel.lua".source
            } \
              ${pkgs.luajit}/bin/luajit ${./modules/cli/todoist-panel-test.lua} && touch $out
          '';
      in
      {
        # legacyPackages, not packages: this is the whole nixpkgs set, and
        # `nix flake check` requires every `packages.<system>.<name>` to be a
        # derivation (`pkgs.system` is a string, so it failed the check).
        # legacyPackages is the output nixpkgs itself uses for exactly this,
        # and `nix build .#<anypkg>` still resolves through it.
        legacyPackages = pkgs;

        checks =
          lib.optionalAttrs (system == "aarch64-darwin") {
            nvim-init-vega = nvimInitCheck "vega" darwinConfigurations.vega;
            hammerspoon-init-vega = hammerspoonInitCheck "vega" darwinConfigurations.vega;
            todoist-panel-vega = todoistPanelCheck "vega" darwinConfigurations.vega;
          }
          // lib.optionalAttrs (system == "x86_64-linux") {
            nvim-init-polaris = nvimInitCheck "polaris" nixosConfigurations.polaris;
          };

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
