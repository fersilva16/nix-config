# Aside — AI browser (https://aside.com).
#
# No Homebrew cask exists yet, so we build the .app straight from the
# vendor DMG. The DMG is LZMA-compressed APFS, which `undmg` can't read —
# `_7zz` (real 7-Zip, has APFS support) extracts the bundle directly.
#
# ponytail: URL + hash are version-pinned. Bump `version` and refresh the
# hash on update; switch to `system.homebrew.casks = [ "aside" ]` once a
# cask lands and delete this derivation.
{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  aside = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "aside";
    version = "1.0.623.1";

    src = pkgs.fetchurl {
      url = "https://releases.aside.com/dev-updater/Aside-${finalAttrs.version}.dmg";
      hash = "sha256-UYtzzFyJpTRrPNVNfYFOJx2SbeLUg2naJJLNgsyCOlY=";
    };

    sourceRoot = ".";

    nativeBuildInputs = [ pkgs._7zz ];

    # `_7zz` flags an unsupported GPT-backup-table stream (harmless), so allow
    # its non-zero exit, then drop the AppleDouble xattr sidecars it emits.
    unpackPhase = ''
      runHook preUnpack
      7zz x "$src" -y || true
      find . -name '*:com.apple.*' -delete
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/Applications
      cp -r Aside.app $out/Applications/
      runHook postInstall
    '';

    meta = {
      description = "AI browser built to do real work for you";
      homepage = "https://aside.com/";
      license = lib.licenses.unfree;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      platforms = lib.platforms.darwin;
    };
  });
in
mkUserModule {
  name = "aside";
  home.home.packages = [ aside ];
}
