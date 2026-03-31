{ mkUserModule, ... }:
mkUserModule {
  name = "firefox";
  system.homebrew.casks = [ "firefox" ];
}
