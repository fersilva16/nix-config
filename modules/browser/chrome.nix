{ mkUserModule, ... }:
mkUserModule {
  name = "chrome";
  casks = [ "google-chrome" ];
}
