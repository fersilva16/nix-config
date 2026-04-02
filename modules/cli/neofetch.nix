{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "neofetch";
  home.home.packages = [ pkgs.neofetch ];
}
