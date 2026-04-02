{ mkSystemModule, pkgs, ... }:
mkSystemModule {
  name = "wget";
  config.environment.systemPackages = [ pkgs.wget ];
}
