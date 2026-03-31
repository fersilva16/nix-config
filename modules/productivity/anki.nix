{ mkUserModule, ... }:
mkUserModule {
  name = "anki";
  system.homebrew.casks = [ "anki" ];
}
