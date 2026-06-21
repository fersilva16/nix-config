{ mkUserModule, ... }:
mkUserModule {
  name = "zotero";
  system.homebrew.casks = [ "zotero" ];
}
