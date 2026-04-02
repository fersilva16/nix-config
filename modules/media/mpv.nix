{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "mpv";
  home.home.packages = [ pkgs.mpv ];
}
