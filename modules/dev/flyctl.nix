{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "flyctl";
  home.home.packages = with pkgs; [ flyctl ];
}
