{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "stern";
  home.home.packages = with pkgs; [ stern ];
}
