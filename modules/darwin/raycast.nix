{ mkUserModule, ... }:
mkUserModule {
  name = "raycast";
  system.homebrew.casks = [ "raycast" ];
}
