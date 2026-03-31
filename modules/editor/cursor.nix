{ mkUserModule, ... }:
mkUserModule {
  name = "cursor";
  system.homebrew.casks = [ "cursor" ];
}
