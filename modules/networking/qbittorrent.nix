{
  mkUserModule,
  forPlatform,
  pkgs,
  ...
}:
mkUserModule {
  name = "qbittorrent";
  casks = [ "qbittorrent" ];
  home = {
    home.packages = forPlatform { linux = [ pkgs.qbittorrent ]; };
  };
}
