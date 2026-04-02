{ mkSystemModule, pkgs, ... }:
mkSystemModule {
  name = "caskaydia-cove";
  config.fonts.packages = [
    pkgs.nerd-fonts.caskaydia-cove
  ];
}
