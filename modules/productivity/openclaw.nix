{ mkUserModule, ... }:
mkUserModule {
  name = "openclaw";
  system.homebrew.casks = [ "openclaw" ];
}
