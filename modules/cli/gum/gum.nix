{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  version = "2.0.0";

  # gum hardcodes ctrl+j for "insert newline" and exposes no keymap surface at
  # all: no flag, no GUM_* env var, no config file. charmbracelet/gum#727 (the
  # issue) and #822 (the PR) are both still open, and v2.0.0's write/options.go
  # still carries exactly one behavioural flag. Patching is the only lever.
  #
  # This needs v2 specifically, not just the patch. nixpkgs ships gum 0.17.0,
  # built on bubbletea v1.3.6, which cannot receive shift+enter at all — the
  # terminal collapses it to a bare CR, so binding the string would be inert.
  # v2.0.0 moved to bubbletea v2, which speaks the kitty keyboard protocol, so
  # "shift+enter" became a key string that can actually match.
  #
  # Built from scratch rather than `pkgs.gum.overrideAttrs` so that nothing in
  # here reads `pkgs.gum` — the overlay below replaces that attribute, and
  # referring to it while defining it is an infinite recursion.
  gum-v2 = pkgs.buildGoModule {
    pname = "gum";
    inherit version;

    src = pkgs.fetchFromGitHub {
      owner = "charmbracelet";
      repo = "gum";
      rev = "v${version}";
      hash = "sha256-M1eLi/Jc8QCc6Mai3Nc42MXRnl5ucafQMiOFL3kLoz4=";
    };

    vendorHash = "sha256-gvTQQOkCVIyKE27dgeQAPM4ZBV2XZnjRtqmEwPbY3Gc=";

    patches = [ ./shift-enter.patch ];

    ldflags = [
      "-s"
      "-w"
      "-X=main.Version=${version}"
    ];

    meta = {
      description = "Glamorous shell scripts (v2, patched: shift+enter inserts a newline)";
      homepage = "https://github.com/charmbracelet/gum";
      license = lib.licenses.mit;
      mainProgram = "gum";
    };
  };
in
mkUserModule {
  name = "gum";

  # modules/dev/linear.nix bakes `pkgs.gum` into its script's PATH at build
  # time, and modules/cli/todoist.nix lists it in runtimeInputs, so putting the
  # patched build only in home.packages would leave those scripts pointing at
  # the unpatched 0.17.0 store path. Override the package set instead, and
  # every consumer follows.
  system.nixpkgs.overlays = [ (_: _: { gum = gum-v2; }) ];

  home.home.packages = [ gum-v2 ];
}
