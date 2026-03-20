{
  lib,
  stdenv,
  fetchFromGitHub,
  bun,
  bun2nix,
  nodejs,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "opencode-anthropic-auth";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "Thesam1798";
    repo = "opencode-anthropic-auth";
    rev = "78ac824951ccb6e39c036f8ff3933dc23a877cea";
    hash = "sha256-VUhShn/Pg3SWW0xjc0TO4bVtlUilnadHbAs+CY3V6nc=";
  };

  nativeBuildInputs = [
    bun
    bun2nix.hook
    nodejs
  ];

  bunDeps = bun2nix.fetchBunDeps {
    bunNix = ./bun.nix;
  };

  buildPhase = ''
    runHook preBuild
    bun run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r dist package.json node_modules $out/

    runHook postInstall
  '';

  meta = {
    description = "OpenCode plugin for Anthropic OAuth authentication";
    homepage = "https://github.com/ex-machina-co/opencode-anthropic-auth";
    license = lib.licenses.mit;
  };
})
