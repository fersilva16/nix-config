{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "paisa";
  version = "0.7.1";

  src = fetchurl {
    url = "https://github.com/ananthakumaran/paisa/releases/download/v${finalAttrs.version}/paisa-app-macos-amd64.dmg";
    hash = "sha256-4g8oimtZB/1I2H1b03w2AjZfGGhqAqFtR5IFqf7sUcE=";
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
