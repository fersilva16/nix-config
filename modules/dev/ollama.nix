{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "ollama";
  home.home.packages = with pkgs; [ ollama ];
}
