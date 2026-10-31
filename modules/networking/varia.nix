# Varia — GTK download manager on aria2 (multi-connection HTTP/FTP, resume).
# Linux-only: no macOS build exists.
{
  mkUserModule,
  forPlatform,
  pkgs,
  ...
}:
mkUserModule {
  name = "varia";
  home = {
    home.packages = forPlatform { linux = [ pkgs.varia ]; };
  };
}
