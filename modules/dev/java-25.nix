{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "java-25";
  home.home.packages = with pkgs; [ temurin-bin-25 ];
}
