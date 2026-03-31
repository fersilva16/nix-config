{ mkUserModule, ... }:
mkUserModule {
  name = "dbeaver";
  system.homebrew.casks = [ "dbeaver-community" ];
}
