{ mkUserModule, ... }:
mkUserModule {
  name = "discord";
  system.homebrew.casks = [ "discord" ];
}
