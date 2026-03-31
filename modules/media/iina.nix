{ mkUserModule, ... }:
mkUserModule {
  name = "iina";
  system.homebrew.casks = [ "iina" ];
}
