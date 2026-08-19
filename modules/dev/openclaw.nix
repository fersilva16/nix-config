{
  inputs,
  system,
  mkUserModule,
  ...
}:
let
  # Reproduce the package set nix-openclaw builds internally: ITS nixpkgs pin
  # plus ITS overlay, exactly as its flake does.
  #
  # Applying the overlay to OUR nixpkgs instead (the obvious move) rebuilds
  # openclaw against our nodejs_22 = 22.22.2 — one patch below the >=22.22.3
  # floor openclaw enforces at startup — so the gateway exits 1 and launchd
  # crash-loops it. Their pin carries nodejs_22 = 22.23.1 deliberately. It also
  # costs the binary cache: garnix publishes builds made against their pin, so
  # rebuilding against ours misses every substitute.
  openclawPkgs = import inputs.nix-openclaw.inputs.nixpkgs {
    inherit system;
    overlays = [ inputs.nix-openclaw.overlays.default ];
  };
in
mkUserModule {
  name = "openclaw";

  system = {
    # Alias the prebuilt attrs the home-manager module resolves off pkgs. It
    # reads `pkgs.openclaw`, `pkgs.openclawPackages` (toolchain overrides, QMD)
    # and `pkgs.openclawRuntimePlugins` internally, so setting
    # `programs.openclaw.package` alone would leave those pointing at the
    # nixpkgs build — which nixpkgs marks insecure ("uses LLMs to parse
    # untrusted content while having full access to system by default") and
    # refuses to evaluate.
    nixpkgs.overlays = [
      (_: _: {
        inherit (openclawPkgs)
          openclaw
          openclaw-app
          openclaw-gateway
          openclawPackages
          openclawRuntimePlugins
          ;
      })
    ];

    # Pre-built openclaw. The flake declares this cache in its own nixConfig,
    # but flake nixConfig does not apply to inputs — without it here, every
    # rebuild compiles a pnpm workspace with native addons (sharp, node-pty)
    # from source. Upstream publishes packages.aarch64-darwin.openclaw here.
    nix.settings = {
      extra-substituters = [ "https://cache.garnix.io" ];
      extra-trusted-public-keys = [
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      ];
    };
  };

  home = {
    imports = [ inputs.nix-openclaw.homeManagerModules.openclaw ];

    programs.openclaw = {
      enable = true;

      # ponytail: workaround for an upstream bug, not decoration. When
      # `instances` is empty, nix-openclaw synthesises a default instance as a
      # plain attrset whose `appDefaults` omits `nixMode` — but config.nix reads
      # `inst.appDefaults.nixMode` unconditionally on darwin, so a bare
      # `enable = true` fails to evaluate on macOS. Declaring the instance routes
      # it through the submodule type, which supplies every default (identical
      # stateDir/logPath/gatewayPort, plus the missing nixMode). Upstream CI
      # misses this because its macOS test declares instances.default too.
      # Remove once nix-openclaw fixes defaultInstance.
      instances.default.config = {
        # The gateway binds loopback only (gateway.mode = "local", 127.0.0.1 and
        # ::1 on 18789), so there is no network surface to authenticate and
        # "none" costs nothing. The alternatives all mean a shared secret, and
        # openclaw.json is a world-readable /nix/store path — a literal token
        # there would be legible to every user on the machine. If this gateway
        # is ever exposed beyond loopback, this must become "token" with the
        # value supplied as a SecretRef (file/exec), never inline.
        gateway.auth.mode = "none";
      };
    };
  };
}
