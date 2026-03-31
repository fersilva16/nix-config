{ mkUserModule, ... }:
mkUserModule {
  name = "notion-calendar";
  system.homebrew.casks = [ "notion-calendar" ];
}
