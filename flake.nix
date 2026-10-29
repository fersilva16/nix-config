{
  description = "My NixOS configuration";

  # Binary caches the hosts need, declared at the flake level so they apply to
  # the very first build of this flake too — a module's nix.settings only lands
  # in nix.conf AFTER the switch that introduces it, so a fresh install (or the
  # rebuild that adds a module) would otherwise compile from source. Nix asks
  # once per machine to trust these; answer y to both prompts (without a TTY
  # they are silently ignored). noctalia.nix and the polaris host still set
  # them in nix.settings so the running system keeps them.
  nixConfig = {
    extra-substituters = [
      "https://noctalia.cachix.org"
      "https://cache.nixos-cuda.org"
    ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

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

    # Floor is brew 6.0.0: nix-darwin's homebrew activation passes
    # `--zap --force-cleanup` to `brew bundle`, and `--force-cleanup` did not
    # exist before 6.0.0 (5.x only had `-f`/`--force`), so an older brew aborts
    # activation with "Error: invalid option: --force-cleanup".
    #
    # Also still satisfies the reason this was pinned in the first place: the
    # cask OS-dependency regression fix (https://github.com/Homebrew/brew/pull/22261),
    # required for casks like stremio and iina that combine `on_arm`/`on_intel`
    # macOS deps with a top-level `depends_on :macos`.
    brew-src = {
      url = "github:Homebrew/brew/6.0.22";
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
    # must follow the host's: quickshell dlopens the system Mesa EGL driver
    # from /run/opengl-driver, which needs the system glibc. On noctalia's
    # own (older) lock the driver fails to load, there is no GL context, and
    # no bar/panel ever maps. Costs noctalia.cachix.org hits (the quickshell
    # fork builds locally; Qt still comes from cache.nixos.org).
    noctalia = {
      url = "github:noctalia-dev/noctalia/legacy-v4";
      inputs.nixpkgs.follows = "nixpkgs-nixos";
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

    # Claude Desktop's official Linux beta (.deb) packaged for Nix; the flake
    # tracks Anthropic's apt repo and bumps hashes hourly. modules/dev/claude.nix
    # callPackages its derivation against the host's nixpkgs, so the follows
    # only keeps a second nixpkgs out of the lock.
    claude-desktop = {
      url = "github:poeck/claude-desktop-nix-flake";
      inputs.nixpkgs.follows = "nixpkgs-nixos";
    };

    # Limi ships everything as one package, limi-suite; users opt in via
    # modules/dev/limi-suite.nix, which installs it and wires the host side.
    # Private repo, hence ssh, but flake.lock pins it, so ssh only runs on
    # `nix flake update limi`. To try local Limi changes, run `limi switch`
    # (no rebuild). Only a change to `lib.host` needs a rebuild with
    # --override-input limi git+file:///home/fernando/limi
    # No nixpkgs follows: Limi builds on its own pin, so a rebuild gets the
    # same derivations as `limi switch` and reuses its cached Rust deps.
    limi = {
      url = "git+ssh://git@github.com/fersilva16/limi";
    };
  };

  outputs =
    { nixpkgs, utils, ... }@inputs:
    let
      inherit (nixpkgs) lib;

      # Every host, keyed by hostname. The factories take the fleet itself so
      # each host can read what the others advertise; `let` is recursive and
      # lazy, so that is a plain reference, not an eager cycle.
      fleet = import ./modules/hosts/fleet.nix {
        mkDarwinHost = import ./lib/mkDarwinHost.nix { inherit inputs fleet; };
        mkNixOSHost = import ./lib/mkNixOSHost.nix { inherit inputs fleet; };
      };

      darwinConfigurations = lib.filterAttrs (_: host: host.class == "darwin") fleet;
      nixosConfigurations = lib.filterAttrs (_: host: host.class == "nixos") fleet;
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
      in
      {
        # legacyPackages, not packages: this is the whole nixpkgs set, and
        # `nix flake check` requires every `packages.<system>.<name>` to be a
        # derivation (`pkgs.system` is a string, so it failed the check).
        # legacyPackages is the output nixpkgs itself uses for exactly this,
        # and `nix build .#<anypkg>` still resolves through it.
        legacyPackages = pkgs;

        # Forcing a host's drvPath evaluates the whole system, so an eval error
        # (e.g. a home file whose `.text = mkIf false …` leaves `source`
        # undefined) fails here, not at the next switch. Discarding the
        # context keeps it eval-only. Each host is checked only on its own
        # system: limi-suite's crate2nix import-from-derivation builds during
        # evaluation, so evaluating the other host would need its platform's
        # builder.
        checks =
          lib.optionalAttrs (system == "aarch64-darwin") {
            eval-vega = pkgs.writeText "eval-vega" (
              builtins.unsafeDiscardStringContext darwinConfigurations.vega.system.drvPath
            );
            nvim-init-vega = nvimInitCheck "vega" darwinConfigurations.vega;
            hammerspoon-init-vega = hammerspoonInitCheck "vega" darwinConfigurations.vega;
          }
          // lib.optionalAttrs (system == "x86_64-linux") {
            eval-polaris = pkgs.writeText "eval-polaris" (
              builtins.unsafeDiscardStringContext nixosConfigurations.polaris.config.system.build.toplevel.drvPath
            );
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
