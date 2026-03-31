{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "wireguard";
  home.home.packages = with pkgs; [ wireguard-tools ];
}
