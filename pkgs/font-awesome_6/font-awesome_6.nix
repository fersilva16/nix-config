{ lib, fetchFromGitHub }:
fetchFromGitHub {
  name = "font-awesome-6.0.0";

  owner = "FortAwesome";
  repo = "Font-Awesome";
  rev = "6.0.0";
  sha256 = "sha256-ZfMiliRAkY4i7lzHX/77TOhe3EJZq3WNkTa4qehXDJQ=";

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
