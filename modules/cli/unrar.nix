{ mkSystemModule, pkgs, ... }:
mkSystemModule {
  name = "unrar";
  config.environment.systemPackages = [ pkgs.unrar ];
}
