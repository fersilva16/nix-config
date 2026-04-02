{ mkUserModule, ... }:
mkUserModule {
  name = "zoom";
  system.homebrew.casks = [ "zoom" ];
}
