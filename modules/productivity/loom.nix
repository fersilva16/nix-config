{ mkUserModule, ... }:
mkUserModule {
  name = "loom";
  system.homebrew.casks = [ "loom" ];
}
