{ mkUserModule, ... }:
mkUserModule {
  name = "slack";
  system.homebrew.casks = [ "slack" ];
}
