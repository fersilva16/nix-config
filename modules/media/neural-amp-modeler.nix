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
in
mkUserModule {
  name = "neural-amp-modeler";
  home = {
    # copyApps puts the app in ~/Applications/Home Manager Apps.
    home.packages = [ nam ];

    # DAWs scan ~/Library/Audio/Plug-Ins; copy real bundles there (plugin hosts
    # and AU validation don't reliably follow symlinks into the store).
    home.activation.neuralAmpModelerPlugins = {
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
