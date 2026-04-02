{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "rust";
  home.home.packages = [ pkgs.rustup ];
}
