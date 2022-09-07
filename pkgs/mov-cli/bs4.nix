{ python310 }:
with python310.pkgs;
buildPythonPackage {
  pname = "bs4";
  version = "0.0.1";

  src = fetchPypi {
    pname = "bs4";
    version = "0.0.1";
    sha256 = "sha256-NuzqH9fMXAxuSh/wdd8m1Q2mR7dTdmJswYbiISiG3To=";
  };

  propagatedBuildInputs = [
    beautifulsoup4
  ];
}
