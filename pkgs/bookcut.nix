{ lib, python310, fetchFromGitHub }:
with python310.pkgs; buildPythonPackage {
  pname = "bookcut";
  version = "1.3.7";

  src = fetchFromGitHub {
    owner = "costis94";
    repo = "bookcut";
    rev = "88a06bf6e7962f6b013b9f45d23886e255d7a9f2";
    sha256 = "sha256-3JwtPnS2Ms5x3Q0ele4gOinHOSb7Kq4ris/+tRuG1M8=";
  };

  doCheck = false;

  propagatedBuildInputs = [
    pandas
    click
    requests
    beautifulsoup4
    pyfiglet
    tqdm
    mechanize
  ];

  meta = with lib; {
    description = "Command Line Interface app to download ebooks";
    homepage = "https://github.com/costis94/bookcut";
    license = licenses.mit;
  };
}
