{
  mkUserModule,
  forPlatform,
  pkgs,
  ...
}:
mkUserModule {
  name = "discord";
  casks = [ "discord" ];
  home = {
    home.packages = forPlatform { linux = [ pkgs.discord ]; };
  };
}
