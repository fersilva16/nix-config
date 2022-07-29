self: super:
super.noto-fonts-cjk-sans.overrideAttrs (_: {
  version = "2.004";

  src = self.fetchFromGitHub {
    owner = "googlefonts";
    repo = "noto-cjk";
    sparseCheckout = "Sans/OTC";
    rev = "9f7f3c38eab63e1d1fddd8d50937fe4f1eacdb1d";
    sha256 = "sha256-i2edZ7Ge0Z3z7KRiozOUhwqU9OoZbhDIDq/5ZN1nmYQ=";
  };

  installPhase = ''
    install -m444 -Dt $out/share/fonts/opentype/noto-cjk Sans/OTC/*.ttc
  '';
})
