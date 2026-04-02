{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  fetchPnpmDeps,
  makeWrapper,
  pkg-config,
  vips,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "figma-developer-mcp";
  version = "0.6.6";

  src = fetchFromGitHub {
    owner = "GLips";
    repo = "Figma-Context-MCP";
    rev = "v${finalAttrs.version}";
    hash = "sha256-PwgNYyA0ZlGWfb5Ax15SzzmxIexp5fJLKuOFwGmEfD8=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm_10
    pnpmConfigHook
    makeWrapper
    pkg-config
  ];

  buildInputs = [ vips ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    fetcherVersion = 3;
    hash = "sha256-+tqfpo1m2GipRgr5R4wsDTfVbCDTpovhZ3WEeswDF54=";
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
    makeWrapper ${nodejs}/bin/node $out/bin/figma-developer-mcp \
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
