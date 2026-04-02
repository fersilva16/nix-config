{ mkUserModule, ... }:
mkUserModule {
  name = "conductor";
  system.homebrew.casks = [ "conductor" ];
}
