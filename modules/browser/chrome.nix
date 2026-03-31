{ mkUserModule, ... }:
mkUserModule {
  name = "chrome";
  system.homebrew.casks = [ "google-chrome" ];
}
