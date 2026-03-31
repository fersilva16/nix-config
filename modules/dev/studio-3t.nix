{ mkUserModule, ... }:
mkUserModule {
  name = "studio-3t";
  system.homebrew.casks = [ "studio-3t-community" ];
}
