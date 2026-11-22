# Apple Color Emoji as the emoji font on Linux desktops, so every fontconfig
# client (GTK/Qt apps, browsers, terminals) draws Apple's emoji. The font is
# samuelngs/apple-emoji-linux's Linux build (CBDT colour bitmaps, which
# FreeType draws well). darwin ships the font itself, so nothing is set there.
#
# Noto Color Emoji comes with fonts.enableDefaultPackages (on with any
# graphical desktop) alongside fonts this host still wants, and fonts.packages
# can't drop one entry from that list. So fontconfig hides it instead: it is
# rejected outright, and a request for it by name gets Apple Color Emoji. A
# fallback alone isn't enough: Chrome's form controls resolve emoji through a
# different fontconfig query than page text and still landed on Noto.
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
      fontconfig = {
        defaultFonts.emoji = [ "Apple Color Emoji" ];
        localConf = ''
          <?xml version="1.0"?>
          <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
          <fontconfig>
            <selectfont>
              <rejectfont>
                <pattern>
                  <patelt name="family"><string>Noto Color Emoji</string></patelt>
                </pattern>
              </rejectfont>
            </selectfont>
            <match target="pattern">
              <test name="family"><string>Noto Color Emoji</string></test>
              <edit name="family" mode="assign" binding="strong"><string>Apple Color Emoji</string></edit>
            </match>
          </fontconfig>
        '';
      };
    };
  };
}
