{ mkUserModule, ... }:
mkUserModule {
  name = "orbstack";
  system.homebrew.casks = [ "orbstack" ];
}
