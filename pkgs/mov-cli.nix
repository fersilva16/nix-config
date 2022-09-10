{ lib, python310, fetchFromGitHub }:
with python310.pkgs; buildPythonPackage {
  pname = "mov-cli";
  version = "0.1.3";

  src = fetchFromGitHub {
    owner = "mov-cli";
    repo = "mov-cli";
    rev = "4bb8d950910a4ec97fc4759092bf8a1fb79834fa";
    sha256 = "sha256-Sfvl2MVquWZSKplyhphyG5WvBA3/EzAOqFo6LxRxEnk=";
  };

  doCheck = false;

  propagatedBuildInputs = [
    beautifulsoup4
    lxml
    click
    httpx
    colorama
  ];

  meta = with lib; {
    description = "An ani-cli like cli tool for movies and webseries";
    homepage = "https://github.com/mov-cli/mov-cli";
    license = licenses.agpl3;
  };
}
