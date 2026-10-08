{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "tart";
  home.home.packages = with pkgs; [ tart ];
}
