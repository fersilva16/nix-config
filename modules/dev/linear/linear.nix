{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  linear-cli-version = "0.3.15";

  linear-cli = pkgs.stdenvNoCC.mkDerivation {
    pname = "linear-cli";
    version = linear-cli-version;

    src =
      {
        aarch64-darwin = pkgs.fetchurl {
          url = "https://github.com/Finesssee/linear-cli/releases/download/v${linear-cli-version}/linear-cli-aarch64-apple-darwin.tar.gz";
          hash = "sha256-Uhr6/uNjkWi/aIkWO4G6gtrMrbQXMgg0AHW+bOQ/HRs=";
        };
      }
      .${pkgs.stdenvNoCC.hostPlatform.system}
        or (throw "linear-cli: unsupported system ${pkgs.stdenvNoCC.hostPlatform.system}");

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
      platforms = [ "aarch64-darwin" ];
      mainProgram = "linear-cli";
    };
  };
in
mkUserModule {
  name = "linear";
  casks = [ "linear" ];

  home =
    { userCfg, ... }:
    {
      # `lin` ships in limi-suite and takes linear-cli from PATH.
      home.packages = [ linear-cli ];

      # omo's `/lin` runs `fish -c lin`, which finds limi-suite's `lin`.
      home.file = lib.mkIf (userCfg.omo-home.enable && userCfg.fish.enable) {
        ".omo/agent/extensions/lin.ts".source = ./lin.ts;
      };
    };
}
