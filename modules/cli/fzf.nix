{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "fzf";
  home.home.packages = with pkgs; [ fzf ];
}
