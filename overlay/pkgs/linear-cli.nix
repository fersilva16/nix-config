{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  version = "0.3.15";

  sources = {
    aarch64-darwin = fetchurl {
      url = "https://github.com/Finesssee/linear-cli/releases/download/v${version}/linear-cli-aarch64-apple-darwin.tar.gz";
      hash = "sha256-Uhr6/uNjkWi/aIkWO4G6gtrMrbQXMgg0AHW+bOQ/HRs=";
    };
  };
in
stdenvNoCC.mkDerivation {
  pname = "linear-cli";
  inherit version;

  src =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "linear-cli: unsupported system ${stdenvNoCC.hostPlatform.system}");

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 linear-cli $out/bin/linear-cli
    runHook postInstall
  '';

  meta = {
    description = "A powerful CLI for Linear.app built with Rust";
    homepage = "https://github.com/Finesssee/linear-cli";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [
      "aarch64-darwin"
    ];
    mainProgram = "linear-cli";
  };
}
