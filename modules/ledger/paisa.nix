{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  paisa = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "paisa";
    version = "0.7.4";

    src = pkgs.fetchurl {
      url = "https://github.com/ananthakumaran/paisa/releases/download/v${finalAttrs.version}/paisa-app-macos-amd64.dmg";
      hash = "sha256-Jn6UdtD9Pet42/g78uDE4rAOjlEo6/LI3e/xiPm86bk=";
    };

    sourceRoot = ".";

    nativeBuildInputs = [ pkgs.undmg ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/Applications
      cp -r *.app $out/Applications

      runHook postInstall
    '';

    meta = {
      description = "Personal finance manager";
      homepage = "https://paisa.fyi/";
      license = lib.licenses.gpl3;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      platforms = lib.platforms.darwin;
    };
  });
in
mkUserModule {
  name = "paisa";
  home = {
    home.packages = [ paisa ];

    home.file."Documents/paisa/paisa.yaml" = {
      source = ./paisa.yaml;
      force = true;
    };
  };
}
