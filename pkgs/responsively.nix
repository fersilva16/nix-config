{ lib, fetchurl, appimageTools }:
let
  pname = "responsively";
  version = "0.18.0";
  name = "${pname}-${version}";
in
appimageTools.wrapType2 {
  inherit version pname;

  src = fetchurl {
    url = "https://github.com/responsively-org/responsively-app/releases/download/v${version}/ResponsivelyApp-${version}.AppImage";
    sha256 = "sha256-KkdFMkgpGqnIqQ3QTJYYj5wa1rHWlPEvnbtMEcNNDUQ=";
  };

  extraInstallCommands = ''
    mv $out/bin/{${name},${pname}}
  '';

  meta = with lib; {
    description = "A modified web browser that helps in responsive web development";
    homepage = "https://responsively.app";
    license = licenses.agpl3;
    platforms = [ "x86_64-linux" ];
  };
}
