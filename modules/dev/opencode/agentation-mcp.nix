{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_22,
  pnpm_10,
  pnpmConfigHook,
  fetchPnpmDeps,
  makeWrapper,
  python3,
}:
let
  # See figma-developer-mcp.nix for context: Node.js 24.15.0 in current
  # nixpkgs crashes pnpm with "Abort trap: 6". Pin the pnpm runtime to
  # nodejs_22 (LTS) which doesn't have the FD-tracking regression.
  pnpm = pnpm_10.override { nodejs = nodejs_22; };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "agentation-mcp";
  version = "3.0.2-unstable-2026-03-25";

  src = fetchFromGitHub {
    owner = "benjitaylor";
    repo = "agentation";
    rev = "7dc5d65378fa901e6eead81d4e2bb62950d49f0b";
    hash = "sha256-qddLnszOYdZZrmtSPoFzh5KTL5Z3n+yXl4C7Hcai7w8=";
  };

  sourceRoot = "${finalAttrs.src.name}/mcp";

  # Remove workspace config so pnpm treats mcp/ as a standalone project
  postUnpack = ''
    chmod -R +w ${finalAttrs.src.name}
    rm -f ${finalAttrs.src.name}/pnpm-workspace.yaml
    rm -f ${finalAttrs.src.name}/package.json
  '';

  nativeBuildInputs = [
    nodejs_22
    pnpm
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
    inherit pnpm;
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
    makeWrapper ${nodejs_22}/bin/node $out/bin/agentation-mcp \
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
