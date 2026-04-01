{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "readwise";
  home.home.packages = [ pkgs.readwise-cli ];
}
