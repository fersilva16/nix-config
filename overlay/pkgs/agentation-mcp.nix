{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  fetchPnpmDeps,
  makeWrapper,
  python3,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "agentation-mcp";
  version = "1.2.0-unstable-2026-03-23";

  src = fetchFromGitHub {
    owner = "benjitaylor";
    repo = "agentation";
    rev = "f0a4a2b9359ed98e64f839e3307e043fe7a0cb8a";
    hash = "sha256-b9bIDCw2EnfrUUXqzRVySPtQ5k9V/R8Et9qGkh7Lqu8=";
  };

  sourceRoot = "${finalAttrs.src.name}/mcp";

  # Remove workspace config so pnpm treats mcp/ as a standalone project
  postUnpack = ''
    chmod -R +w ${finalAttrs.src.name}
    rm -f ${finalAttrs.src.name}/pnpm-workspace.yaml
    rm -f ${finalAttrs.src.name}/package.json
  '';

  nativeBuildInputs = [
    nodejs
    pnpm_10
    pnpmConfigHook
    makeWrapper
    python3 # needed by better-sqlite3 node-gyp build
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs)
      pname
      version
      src
      sourceRoot
      ;
    fetcherVersion = 3;
    hash = "sha256-aEfhVfaAJaHhLUhm3lASlaE+2/f5rLqnpWAKRZgIKU4=";
    postUnpack = ''
      chmod -R +w ${finalAttrs.src.name}
      rm -f ${finalAttrs.src.name}/pnpm-workspace.yaml
      rm -f ${finalAttrs.src.name}/package.json
    '';
  };

  buildPhase = ''
    runHook preBuild
    pnpm build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/agentation-mcp
    cp -r dist package.json node_modules $out/lib/agentation-mcp/

    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/agentation-mcp \
      --add-flags "$out/lib/agentation-mcp/dist/cli.js"

    runHook postInstall
  '';

  meta = {
    description = "MCP server for Agentation — visual feedback for AI coding agents";
    homepage = "https://github.com/benjitaylor/agentation";
    license = lib.licenses.unfree; # PolyForm Shield 1.0.0
    mainProgram = "agentation-mcp";
  };
})
