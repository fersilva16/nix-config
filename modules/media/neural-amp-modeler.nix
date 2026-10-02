# Neural Amp Modeler — guitar amp simulator: standalone app + AU/VST3 plugins.
# Not in nixpkgs or Homebrew, so this repackages the official release: an APFS
# DMG (7zz) holding a flat installer pkg (xar) whose component payloads are
# gzipped cpio archives. v0.7.14/v0.7.15 ship no binaries; 0.7.13 is the newest
# release with a macOS build.
{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  nam = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "neural-amp-modeler";
    version = "0.7.13";

    src = pkgs.fetchurl {
      url = "https://github.com/sdatkinson/NeuralAmpModelerPlugin/releases/download/v${finalAttrs.version}/NeuralAmpModeler-v${finalAttrs.version}-mac.dmg";
      hash = "sha256-6c6npAn9Fn4FMU1COimOyzsskV66L4pRTuDEinDzkXM=";
    };

    nativeBuildInputs = [
      pkgs._7zz
      pkgs.xar
      pkgs.cpio
    ];

    unpackPhase = ''
      runHook preUnpack
      7zz x -y "$src" >/dev/null
      xar -xf "NeuralAmpModeler Installer.pkg"
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      payload() {
        mkdir -p "$2"
        gzip -dc "NeuralAmpModeler_$1.pkg/Payload" | (cd "$2" && cpio -idm --quiet)
      }
      payload APP "$out/Applications"
      payload AU "$out/Library/Audio/Plug-Ins/Components"
      payload VST3 "$out/Library/Audio/Plug-Ins/VST3"
      rm -f "$out"/Library/Audio/Plug-Ins/*/._*
      runHook postInstall
    '';

    meta = {
      description = "Neural Amp Modeler standalone app and AU/VST3 plugins";
      homepage = "https://www.neuralampmodeler.com/";
      license = lib.licenses.mit;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      platforms = lib.platforms.darwin;
    };
  });
  plugins = "${nam}/Library/Audio/Plug-Ins";

  # Starter library, read-only from the store: community amp captures (GPL-3)
  # and a collection of freely shared cab IR packs (incl. a few more .nam rigs).
  models = pkgs.fetchFromGitHub {
    owner = "pelennor2170";
    repo = "NAM_models";
    rev = "944ca6718581c60cc5365586d2f378d740e181f3";
    hash = "sha256-r4gqBzW7bTNly6LGr0/W9rNXc4M3nO0K3mCk0zO8Gbw=";
  };
  # The .wav files live in Git LFS; GitHub tarballs only carry the pointers.
  irs = pkgs.fetchgit {
    url = "https://github.com/fnpngn/IR";
    rev = "a8179cf05a84045c3600744ce8f905382a81fb17";
    fetchLFS = true;
    hash = "sha256-JxcPejwzSYTKGJU8ojUXth3NLclKAH1k5LPmHQPlLwk=";
  };
in
mkUserModule {
  name = "neural-amp-modeler";
  home.home = {
    # copyApps puts the app in ~/Applications/Home Manager Apps.
    packages = [ nam ];

    # The samples are copied rather than linked: /nix is a nobrowse volume, so
    # NAM's open panel can't browse into store symlinks. Each source gets its
    # own subfolder (mirrored with --delete), leaving room for your own files.
    # Runs after linkGeneration so the old store symlinks are already gone.
    activation.neuralAmpModelerLibrary = {
      after = [ "linkGeneration" ];
      before = [ ];
      data = ''
        lib="$HOME/Music/NAM"
        mkdir -p "$lib/Models/pelennor2170" "$lib/IRs/fnpngn"
        ${pkgs.rsync}/bin/rsync -a --delete --chmod=u+w ${models}/ "$lib/Models/pelennor2170/"
        ${pkgs.rsync}/bin/rsync -a --delete --chmod=u+w ${irs}/ "$lib/IRs/fnpngn/"
      '';
    };

    # DAWs scan ~/Library/Audio/Plug-Ins; copy real bundles there (plugin hosts
    # and AU validation don't reliably follow symlinks into the store).
    activation.neuralAmpModelerPlugins = {
      after = [ "writeBoundary" ];
      before = [ ];
      data = ''
        dst="$HOME/Library/Audio/Plug-Ins"
        mkdir -p "$dst/Components" "$dst/VST3"
        ${pkgs.rsync}/bin/rsync -a --delete --chmod=u+w \
          ${plugins}/Components/NeuralAmpModeler.component/ "$dst/Components/NeuralAmpModeler.component/"
        ${pkgs.rsync}/bin/rsync -a --delete --chmod=u+w \
          ${plugins}/VST3/NeuralAmpModeler.vst3/ "$dst/VST3/NeuralAmpModeler.vst3/"
      '';
    };
  };
}
