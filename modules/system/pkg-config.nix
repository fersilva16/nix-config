{ mkSystemModule, pkgs, ... }:
mkSystemModule {
  name = "pkg-config";
  config.environment.systemPackages = [ pkgs.pkg-config ];
}
