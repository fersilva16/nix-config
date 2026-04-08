{ pkgs }:
let
  # Direnv auto-loader plugin: upstream source fetched from GitHub and
  # patched locally.  See patches/direnv-plugin.patch for the rationale
  # (shared-server `session.created` workaround + `shell.env` hook).
  opencode-direnv-plugin = pkgs.applyPatches {
    name = "opencode-direnv-patched";
    src = pkgs.fetchFromGitHub {
      owner = "simonwjackson";
      repo = "opencode-direnv";
      rev = "f257fa7f7e19ea8722fdfe546c2cb8b736d9387d";
      hash = "sha256-5fmyNIQjF5v8TYWRsGMtaWCj9KxoQimX5/XTUcl65kU=";
    };
    patches = [ ./patches/direnv-plugin.patch ];
  };
in
{
  home = {
    programs.opencode.settings.plugin = [
      "file://${opencode-direnv-plugin}/src/index.ts"
    ];
  };
}
