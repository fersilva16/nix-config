{ mkUserModule, ... }:
mkUserModule {
  name = "zen";
  system.homebrew.casks = [ "zen-browser" ];
}
