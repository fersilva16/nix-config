{ mkUserModule, ... }:
mkUserModule {
  name = "zen";
  casks = [ "zen-browser" ];
}
