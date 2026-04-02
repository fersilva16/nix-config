{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "glab";
  home.home.packages = [ pkgs.glab ];
}
