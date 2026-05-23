{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_22,
  pnpm_10,
  pnpmConfigHook,
  fetchPnpmDeps,
  makeWrapper,
  pkg-config,
  vips,
}:
let
  # Workaround for Node.js 24.15.0 bug that crashes pnpm with "Abort trap: 6"
  # after stricter file descriptor tracking flagged pnpm's fs monkey-patches.
  # Channel's older nodejs 24.14.0 works fine; until upstream Node ships a fix,
  # pin the pnpm runtime to nodejs_22 (stable LTS) which doesn't exhibit the
  # FD-tracking regression. The fetchPnpmDeps `pnpm` arg controls only the
  # pnpm binary used to populate the offline store — runtime use of the
  # output by downstream builds is unaffected.
  pnpm = pnpm_10.override { nodejs = nodejs_22; };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "figma-developer-mcp";
  version = "0.11.0";

  src = fetchFromGitHub {
    owner = "GLips";
    repo = "Figma-Context-MCP";
    rev = "v${finalAttrs.version}";
    hash = "sha256-VX7CyYIrHCkl/e6LoUYqXdpxLWhjRBLrWL6Azn8Lwzs=";
  };

  nativeBuildInputs = [
    nodejs_22
    pnpm
    pnpmConfigHook
    makeWrapper
    pkg-config
  ];

  buildInputs = [ vips ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 3;
    hash = "sha256-yPlXV2bcBOSzyxH+y6Vajm+mv2+uHJpcOf7J9Ozlh+w=";
  };

  buildPhase = ''
    runHook preBuild
    pnpm build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/figma-developer-mcp
    cp -r dist package.json node_modules $out/lib/figma-developer-mcp/

    mkdir -p $out/bin
    makeWrapper ${nodejs_22}/bin/node $out/bin/figma-developer-mcp \
      --add-flags "$out/lib/figma-developer-mcp/dist/bin.js"

    runHook postInstall
  '';

  meta = {
    description = "MCP server providing Figma layout information to AI coding agents";
    homepage = "https://github.com/GLips/Figma-Context-MCP";
    license = lib.licenses.mit;
    mainProgram = "figma-developer-mcp";
  };
})
