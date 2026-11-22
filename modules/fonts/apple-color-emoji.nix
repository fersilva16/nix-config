# Apple Color Emoji as the emoji font on Linux desktops, so every fontconfig
# client (GTK/Qt apps, browsers, terminals) draws Apple's emoji. The font is
# samuelngs/apple-emoji-linux's Linux build (CBDT color bitmaps, which
# FreeType draws well). darwin ships the font itself, so nothing is set there.
#
# Apple's is the only color emoji font: with Noto Color Emoji merely behind it
# in the emoji list, Chrome's form controls still drew Noto. Noto Color Emoji
# comes with fonts.enableDefaultPackages (on with any graphical desktop), and
# fonts.packages can't drop one entry from that list, so the defaults go off
# and the rest of nixpkgs' list (fonts/packages.nix) is installed here instead.
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
      enableDefaultPackages = false;
      packages = with pkgs; [
        apple-color-emoji
        dejavu_fonts
        freefont_ttf
        gyre-fonts
        liberation_ttf
        unifont
        noto-fonts-cjk-sans
        noto-fonts-cjk-serif
      ];
      fontconfig.defaultFonts.emoji = [ "Apple Color Emoji" ];
    };
  };
}
