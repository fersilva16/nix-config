{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "krita";
  home.home.packages = [ pkgs.krita ];
}
