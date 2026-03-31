{ mkUserModule, ... }:
mkUserModule {
  name = "spotify";
  system.homebrew.casks = [ "spotify" ];
}
