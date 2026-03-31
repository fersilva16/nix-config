{ mkUserModule, ... }:
mkUserModule {
  name = "granola";
  system.homebrew.casks = [ "granola" ];
}
