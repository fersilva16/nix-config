{ mkUserModule, ... }:
mkUserModule {
  name = "sparkmail";
  system.homebrew.casks = [ "readdle-spark" ];
}
