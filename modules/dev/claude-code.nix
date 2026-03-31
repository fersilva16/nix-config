{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "claude-code";
  home.home.packages = with pkgs; [ claude-code ];
}
