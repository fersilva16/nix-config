{ pkgs }:
let
  # Anthropic OAuth plugin: upstream source fetched from GitHub and
  # patched locally.  See patches/anthropic-auth-fix-token-url.patch
  # for the rationale (token endpoint moved from platform.claude.com
  # to api.anthropic.com, and bare-code state fallback for code exchange).
  anthropic-auth = pkgs.applyPatches {
    name = "opencode-anthropic-auth-patched";
    src = pkgs.fetchFromGitHub {
      owner = "ex-machina-co";
      repo = "opencode-anthropic-auth";
      rev = "v1.8.3";
      hash = "sha256-HbrQ+hPP2PRO0eUAZclYU8VrGZtrJtx1T7iE+IeRORw=";
    };
    patches = [ ./patches/anthropic-auth-fix-token-url.patch ];
  };
in
{
  home = {
    programs.opencode.settings.plugin = [
      "file://${anthropic-auth}/src/index.ts"
    ];
  };
}
