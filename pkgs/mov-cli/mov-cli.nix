{ lib, python310, fetchFromGitHub, bs4 }:
with python310.pkgs; buildPythonPackage {
  pname = "mov-cli";
  version = "0.1.3";

  src = fetchFromGitHub {
    owner = "mov-cli";
    repo = "mov-cli";
    rev = "d0a40a62521c2a08ec784f76dd7fe9e623c5dbf8";
    sha256 = "sha256-7KK7xNWCOgUulqxvF7GQe8MPIGIH0DSLKByB8C93164=";
  };

  doCheck = false;

  propagatedBuildInputs = [
    lxml
    colorama
    httpx
    pypresence
    click
    bs4
  ];

  meta = with lib; {
    description = "An ani-cli like cli tool for movies and webseries";
    homepage = "https://github.com/mov-cli/mov-cli";
    license = licenses.agpl3;
  };
}
