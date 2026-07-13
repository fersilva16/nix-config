{ mkUserModule, ... }:
mkUserModule {
  name = "dbeaver";
  casks = [ "dbeaver-community" ];
}
