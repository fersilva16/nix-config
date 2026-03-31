{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "doppler";
  home.home.packages = with pkgs; [ doppler ];
}
