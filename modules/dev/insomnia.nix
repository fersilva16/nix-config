{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "insomnia";
  home.home.packages = [ pkgs.insomnia ];
}
