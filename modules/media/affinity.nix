{ mkUserModule, ... }:
mkUserModule {
  name = "affinity";
  system.homebrew.casks = [ "affinity" ];
}
