{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "awscli";
  home.home.packages = with pkgs; [ awscli2 ];
}
