self: super:
super.noto-fonts-cjk-sans.overrideAttrs (_: {
  version = "2.000";

  src = self.fetchFromGitHub {
    owner = "googlefonts";
    repo = "noto-cjk";
    sparseCheckout = "Serif/OTC";
    rev = "9f7f3c38eab63e1d1fddd8d50937fe4f1eacdb1d";
    sha256 = "sha256-ajqVn+HUfqvc30bbWYnzkj0z/VD3jX+U/Rxepad6vKI=";
  };

  installPhase = ''
    install -m444 -Dt $out/share/fonts/opentype/noto-cjk Serif/OTC/*.ttc
  '';
})
