{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  antiburn = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "antiburn";
    version = "0.3.3";

    src = pkgs.fetchurl {
      url = "https://github.com/antiburn/antiburn/releases/download/antiburn-v${finalAttrs.version}/antiburn_${finalAttrs.version}_aarch64.app.tar.gz";
      hash = "sha256-gPUcsXluc2Diyz5/BknUMm+gjmNCegxlZFNnW4W9akM=";
    };

    sourceRoot = ".";

    # Tauri ships a hardened-runtime signed bundle — strip/patchelf would
    # invalidate the signature and macOS would refuse to launch it.
    dontFixup = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/Applications
      cp -r antiburn.app $out/Applications

      runHook postInstall
    '';

    meta = {
      description = "Local-first visibility into your AI coding-agent sessions";
      homepage = "https://antiburn.ai/";
      license = lib.licenses.mit;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      platforms = [ "aarch64-darwin" ];
    };
  });
in
mkUserModule {
  name = "antiburn";
  home.home.packages = [ antiburn ];
}
