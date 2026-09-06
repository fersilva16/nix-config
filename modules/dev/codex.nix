{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "codex";
  home.home.packages = with pkgs; [ codex ];
}
