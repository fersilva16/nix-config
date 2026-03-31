{ mkUserModule, ... }:
mkUserModule {
  name = "steam";
  system.homebrew.casks = [ "steam" ];
}
