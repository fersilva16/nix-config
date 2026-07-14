{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "feh";
  home = {
    home.packages = with pkgs; [ feh ];
  };
}
