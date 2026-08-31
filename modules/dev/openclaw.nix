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
  # crash-loops it. Their pin carries nodejs_22 = 22.23.1 deliberately.
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

    # No binary cache for openclaw: it built on garnix, and garnix shut its
    # hosted service down on 2026-07-15 (open-sourced as garnix-io/garnix-ci),
    # then dropped cache.garnix.io from DNS on 2026-08-17. Declaring a dead
    # substituter only bought ~4s of retry backoff per nix run. So every hash
    # bump now compiles a pnpm workspace with native addons (sharp, node-pty)
    # from source. nix-openclaw's own nixConfig still points at the dead host,
    # but flake nixConfig does not apply to inputs, so it costs us nothing.
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
