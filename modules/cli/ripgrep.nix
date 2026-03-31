{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "ripgrep";
  home.home.packages = with pkgs; [ ripgrep ];
}
