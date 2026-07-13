{ mkUserModule, ... }:
mkUserModule {
  name = "sparkmail";
  casks = [ "readdle-spark" ];
}
