{ mkUserModule, ... }:
mkUserModule {
  name = "warp";
  system.homebrew.casks = [ "warp" ];
}
