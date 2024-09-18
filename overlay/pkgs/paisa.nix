{ lib, stdenvNoCC, fetchurl, undmg }:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "paisa";
  version = "0.7.0";

  src = fetchurl {
    url = "https://github.com/ananthakumaran/paisa/releases/download/v${finalAttrs.version}/paisa-app-macos-amd64.dmg";
    hash = "sha256-zCV6vrmhCYhoNvQdBuA5mcDx0Flz2i5JEV6hWGfpoYk=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [ undmg ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/Applications
    cp -r *.app $out/Applications

    runHook postInstall
  '';

  meta = with lib; {
    description = "Personal finance manager";
    homepage = "https://paisa.fyi/";
    license = licenses.gpl3;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = platforms.darwin;
  };
})
