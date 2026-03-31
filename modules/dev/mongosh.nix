{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "mongosh";
  home.home.packages = with pkgs; [
    mongosh
    mongodb-tools
  ];
}
