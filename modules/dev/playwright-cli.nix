{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  playwright-cli = pkgs.buildNpmPackage rec {
    pname = "playwright-cli";
    version = "0.1.8";

    src = pkgs.fetchFromGitHub {
      owner = "microsoft";
      repo = "playwright-cli";
      rev = "v${version}";
      hash = "sha256-8f/wFO4hSytpy3kEPyScoMWXWyeTl/SKoc3vD7xYaKo=";
    };

    npmDepsHash = "sha256-DK+nTRdVKznerAMK7McCCgr2OK4GXymbmgyR9qU/aH4=";

    # Playwright's postinstall downloads browser binaries — skip in sandbox.
    # Browsers are fetched at runtime on first use.
    env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";

    # No build step — the entry point is plain JS.
    dontNpmBuild = true;

    meta = {
      description = "CLI for Playwright browser automation — token-efficient alternative to Playwright MCP";
      homepage = "https://github.com/microsoft/playwright-cli";
      license = lib.licenses.asl20;
      mainProgram = "playwright-cli";
    };
  };
in
mkUserModule {
  name = "playwright-cli";
  home.home.packages = [ playwright-cli ];
}
