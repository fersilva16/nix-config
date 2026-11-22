# Apple Color Emoji as the emoji font on Linux desktops, so every fontconfig
# client (GTK/Qt apps, browsers, terminals) draws Apple's emoji. The font is
# samuelngs/apple-emoji-linux's Linux build (CBDT colour bitmaps, which
# FreeType draws well). Noto Color Emoji stays as the fallback for anything
# it lacks. darwin ships the font itself, so nothing is set there.
{
  mkSystemModule,
  forPlatform,
  pkgs,
  lib,
  ...
}:
let
  tag = "macos-26-20260722-484daf4e";

  apple-color-emoji = pkgs.stdenvNoCC.mkDerivation {
    pname = "apple-color-emoji";
    version = lib.removePrefix "macos-" tag;

    src = pkgs.fetchurl {
      url = "https://github.com/samuelngs/apple-emoji-linux/releases/download/${tag}/AppleColorEmoji-Linux.ttf";
      hash = "sha256-43x69iZaxKCvbVe8ZehhCad22ZZug0MzRVf2PaSCUW8=";
    };

    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      install -Dm444 $src $out/share/fonts/truetype/AppleColorEmoji.ttf
      runHook postInstall
    '';

    meta = {
      description = "Apple Color Emoji built for Linux";
      homepage = "https://github.com/samuelngs/apple-emoji-linux";
      # The build scripts are MIT; the glyphs are Apple's.
      license = lib.licenses.unfree;
      platforms = lib.platforms.linux;
    };
  };
in
mkSystemModule {
  name = "apple-color-emoji";
  config = forPlatform {
    linux.fonts = {
      packages = [ apple-color-emoji ];
      fontconfig.defaultFonts.emoji = [
        "Apple Color Emoji"
        "Noto Color Emoji"
      ];
    };
  };
}
