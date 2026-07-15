{
  mkUserModule,
  forPlatform,
  pkgs,
  ...
}:
mkUserModule {
  name = "chrome";
  casks = [ "google-chrome" ];
  home = {
    home.packages = forPlatform { linux = [ pkgs.google-chrome ]; };
  };
}
