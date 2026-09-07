# antiburn built from source, so the OpenCode scan fix can be patched in.
#
# Upstream ships a Developer-ID signed, notarized .app. We cannot patch that
# bundle without invalidating the signature, so we build the Tauri app
# ourselves and let the toolchain ad-hoc sign it. What that costs is small
# and one-time: macOS re-prompts for the four TCC folder grants and for
# notification permission, and the team-scoped
# `com.apple.developer.usernotifications.communication` entitlement (rich
# "communication" notifications) cannot be claimed ad-hoc. Nothing else is
# lost — antiburn stores nothing in the Keychain and uses no
# security-scoped bookmarks.
{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  runCommand,
  jq,
  moreutils,
  pnpm_10,
  fetchPnpmDeps,
  pnpmConfigHook,
  nodejs,
  cargo-tauri,
}:
let
  # nixpkgs has no pnpm_11, and the repo's pnpm-workspace.yaml uses pnpm 11
  # syntax that pnpm 10 rejects (`allowBuilds` keyed by a URL spec ->
  # ERR_PNPM_INVALID_VERSION_UNION). pnpm is just an npm tarball, so a
  # version+hash override is enough.
  #
  # The relink is required: pnpm 11 moved the real entry point to pnpm.mjs
  # and left pnpm.cjs as a non-executable shim, but generic.nix still
  # symlinks bin/pnpm -> pnpm.cjs, which fails with "Permission denied".
  pnpm_11 =
    (pnpm_10.override {
      version = "11.6.0";
      hash = "sha256-oBYpSdGrGeEuizzZ8PWe8C1750oouAbPf0n7f0wH5c4=";
    }).overrideAttrs
      (old: {
        postInstall = (old.postInstall or "") + ''
          ln -sf $out/libexec/pnpm/bin/pnpm.mjs $out/bin/pnpm
          ln -sf $out/libexec/pnpm/bin/pnpx.mjs $out/bin/pnpx
        '';
      });

  # pnpmConfigHook carries its own copy of the same unsupported `pnpm config
  # set manage-package-manager-versions false` call as the fetcher, and runs
  # it at build time. Same reasoning, same fix — but makeSetupHook builds
  # with a fixed buildCommand and never runs postInstall, so the hook has to
  # be copied and patched rather than overridden. Copying the whole output
  # preserves nix-support/propagated-build-inputs, so propagation survives.
  pnpmConfigHook' = runCommand "pnpm-config-hook-pnpm11" { } ''
    cp -r ${pnpmConfigHook} $out
    chmod -R u+w $out
    substituteInPlace $out/nix-support/setup-hook \
      --replace-fail 'pnpm config set manage-package-manager-versions false' true
  '';
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "antiburn";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "antiburn";
    repo = "antiburn";
    rev = "fc5921447a8f030e525b2a95cf0568a3f25f99a4";
    hash = "sha256-a63FNfD6X6b29TcUbB3qvquRW10v6mlmSaSYpn1STuQ=";
  };

  # Not passed to fetchPnpmDeps or cargoLock below: both read the unpatched
  # src, and these patches only touch Rust, so neither hash moves. Order
  # matters — cluster-join-order.patch is cut against the tree
  # sqlite-connection-reuse.patch leaves behind.
  patches = [
    ./sqlite-connection-reuse.patch
    ./cluster-join-order.patch
  ];

  # Only the desktop app is needed to produce the frontend bundle. The
  # workspace root's devDependencies are lint/CI tooling (secretlint, and an
  # aislop fork pulled from a codeload tarball); scoping them out avoids
  # fetching them and avoids ERR_PNPM_NO_OFFLINE_TARBALL on their transitive
  # deps, which the fetcher does not materialize.
  pnpmWorkspaces = [ "@antiburn/desktop" ];

  # nixpkgs' fetcher hardcodes `pnpm config set
  # manage-package-manager-versions false` into its installPhase, ahead of
  # any hook we could use. pnpm 11 dropped that key from the global config
  # and errors out (ERR_PNPM_CONFIG_SET_UNSUPPORTED_YAML_CONFIG_KEY). The
  # setting exists to stop pnpm self-managing a version mismatch against
  # package.json's `packageManager` field — ours is exactly the pinned
  # 11.6.0, so there is no mismatch to manage and dropping the call is a
  # no-op for us.
  pnpmDeps =
    (fetchPnpmDeps {
      inherit (finalAttrs)
        pname
        version
        src
        pnpmWorkspaces
        ;
      pnpm = pnpm_11;
      fetcherVersion = 3;
      hash = "sha256-OuZZ0S0nxH1UIr9lIJbBTSJXEaBGVr/+n6tyXGsmcpk=";
    }).overrideAttrs
      (old: {
        installPhase =
          builtins.replaceStrings [ "pnpm config set manage-package-manager-versions false" ] [ "true" ]
            old.installPhase;
      });

  postPatch = ''
    # Updater artifacts need upstream's minisign key, which we do not have.
    #
    # Blanking the public key is the other half of that same decision, and it
    # is upstream's own off-switch: `install_updater` returns early on an empty
    # `plugins.updater.pubkey`, so the plugin is never registered and no check
    # ever reaches the network. Nix owns this install — the app lives in the
    # read-only store, where a self-update can only fail (observed: "Cross-device
    # link (os error 18)" after downloading the whole payload). Leaving the key
    # in place buys a download every six hours and an update nudge for an
    # install that cannot happen; `darwin-rebuild` is the upgrade path.
    jq '.bundle.createUpdaterArtifacts = false | .plugins.updater.pubkey = ""' \
      apps/desktop/src-tauri/tauri.conf.json \
      | sponge apps/desktop/src-tauri/tauri.conf.json

    # The repo pins rust 1.97; nixpkgs is on 1.94. The pin is a floor, not a
    # feature requirement — both cargo workspaces `cargo check` clean on 1.94.
    # Every manifest needs it, not just the two roots: workspace members such
    # as antiburn-trace carry their own pin and cargo fails on the first one.
    find . -name Cargo.toml -exec sed -i '/^rust-version = /d' {} +
  '';

  # pnpm 11 re-applies minimumReleaseAge/trustPolicy to every lockfile entry
  # on install, and that verification talks to the registry — which the build
  # sandbox has no network for, so it blocks forever (observed: pnpm asleep at
  # 0% CPU with zero connections). The lockfile here is trusted base: it comes
  # from a content-hashed source derivation and the packages themselves are
  # already pinned by the pnpmDeps hash, so re-verifying publish dates adds
  # nothing this build can act on.
  pnpmInstallFlags = [ "--trust-lockfile" ];

  cargoRoot = "apps/desktop/src-tauri";
  buildAndTestSubdir = finalAttrs.cargoRoot;

  # cargoLock (per-crate fetchurl) rather than cargoHash (fetchCargoVendor).
  # fetchCargoVendor pulls all 649 crates inside one fixed-output derivation
  # whose retry list is [500, 502, 503, 504] — crates.io rate-limits with
  # 403, which is not retried, so a single throttled crate fails the whole
  # vendor and a different crate loses the lottery on every run. Nix's own
  # fetchurl retries and caches each crate independently, so throttling
  # costs one crate instead of the entire download.
  cargoLock = {
    lockFile = "${finalAttrs.src}/apps/desktop/src-tauri/Cargo.lock";
    outputHashes = {
      "tauri-nspanel-2.1.0" = "sha256-oqkQCTe4ohZYoTEPAJfsGC0RGVwaHrEik9iCOKbxPh0=";
      "tray-icon-0.24.1" = "sha256-oFg0UkkSvId5KkfwnLO09LKoyzZC5HAdT3b9PjeqHLk=";
    };
  };

  # Upstream's suite expects a populated session store and network fixtures.
  doCheck = false;

  nativeBuildInputs = [
    jq
    moreutils
    pnpmConfigHook'
    pnpm_11
    nodejs
    cargo-tauri.hook
  ];

  meta = {
    description = "Local-first visibility into your AI coding-agent sessions";
    homepage = "https://antiburn.ai/";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    broken = !stdenv.hostPlatform.isDarwin;
  };
})
