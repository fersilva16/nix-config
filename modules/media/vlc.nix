{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "vlc";
  home.home.packages = [ pkgs.vlc ];
}
