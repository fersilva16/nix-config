{ mkUserModule, ... }:
mkUserModule {
  name = "windows-app";
  system.homebrew.casks = [ "windows-app" ];
}
