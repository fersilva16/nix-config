{ mkUserModule, ... }:
mkUserModule {
  name = "calibre";
  system.homebrew.casks = [ "calibre" ];
}
