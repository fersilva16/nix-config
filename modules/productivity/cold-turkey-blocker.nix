{ mkUserModule, ... }:
mkUserModule {
  name = "cold-turkey-blocker";
  system.homebrew.casks = [ "cold-turkey-blocker" ];
}
