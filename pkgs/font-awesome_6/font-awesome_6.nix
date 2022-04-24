{ lib, fetchFromGitHub }:
fetchFromGitHub {
  name = "font-awesome-6.1.1";

  owner = "FortAwesome";
  repo = "Font-Awesome";
  rev = "28e297f07af26f148c15e6cbbd12cea3027371d3";
  sha256 = "sha256-BjK1PJQFWtKDvfQ2Vh7BoOPqYucyvOG+2Pu/Kh+JpAA=";

  postFetch = ''
    tar xf $downloadedFile --strip=1
    install -m444 -Dt $out/share/fonts/opentype {fonts,otfs}/*.otf
  '';

  meta = with lib; {
    description = "Font Awesome - OTF font";
    longDescription = ''
      Font Awesome gives you scalable vector icons that can instantly be customized.
      This package includes only the OTF font. For full CSS etc. see the project website.
    '';
    homepage = "https://fontawesome.com/";
    license = licenses.ofl;
    platforms = platforms.all;
  };
}
