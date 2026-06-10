{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  av-version = "0.1.40";

  av = pkgs.stdenvNoCC.mkDerivation {
    pname = "av";
    version = av-version;

    src =
      {
        aarch64-darwin = pkgs.fetchurl {
          url = "https://github.com/aviator-co/av/releases/download/v${av-version}/av_${av-version}_darwin_arm64.tar.gz";
          hash = "sha256-N1H9al6N8/LjXDz44pKBrhyktrAajUwxrsW0kDivYwI=";
        };
      }
      .${pkgs.stdenvNoCC.hostPlatform.system}
        or (throw "av: unsupported system ${pkgs.stdenvNoCC.hostPlatform.system}");

    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      install -Dm755 av $out/bin/av
      runHook postInstall
    '';

    meta = {
      description = "Aviator CLI for managing stacked pull requests";
      homepage = "https://github.com/aviator-co/av";
      license = lib.licenses.mit;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      platforms = [ "aarch64-darwin" ];
      mainProgram = "av";
    };
  };
in
mkUserModule {
  name = "av";
  requires = [ "git" ];
  home.home.packages = [ av ];
}
