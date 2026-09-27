{ mkUserModule, pkgs, ... }:
let
  # nixpkgs ships 2.1.263, and Opus 5.5 needs 2.1.280+: the API rejects it
  # outright on older builds. That also breaks omo, whose
  # anthropic-subscription lane drives this binary and silently falls back to
  # opus-5. The derivation only reads version + the platform's binary and
  # checksum, both from ${version}/manifest.zst.json upstream. Drop this once
  # nixpkgs catches up.
  claude-code = pkgs.claude-code.override {
    manifest = {
      version = "2.1.283";
      platforms.darwin-arm64 = {
        binary = "claude.zst";
        checksum = "485d6883c023368800626e0d1f2e4382c3e1bdc760fae12cb2f6e3054f218eec";
      };
    };
  };
in
mkUserModule {
  name = "claude-code";
  home.home.packages = [ claude-code ];
}
